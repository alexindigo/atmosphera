pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// One ordered channel for durable history and pending/live original claims.
// The renderer is not part of this protocol: it only receives owned inputs.
Scope {
  id: root
  property string stageDirectory: ""
  property var _store: null
  property var _pending: ({})
  property var _commands: []
  property var _live: []
  property var _waiting: ({})
  property string _liveKey: ""
  property int _sequence: 0
  property bool _starting: false
  property int _retryDelay: 100

  function open(directory, history, callback) {
    _store = {
      directory: directory,
      history: history
    };
    _history(true, undefined, callback);
  }

  function update(paths, rows, callback) {
    const key = JSON.stringify(paths);
    if (key !== _liveKey || rows !== undefined) {
      _liveKey = key;
      _live = paths;
      _history(false, rows, callback);
    }
  }

  function _history(load, rows, callback) {
    if (!_store)
      return;
    _send({
            action: "history",
            store: _store,
            load: load,
            live: _live,
            rows: typeof rows === "function" ? rows() : rows,
            wanted: Object.keys(_pending)
          }, reply => {
            if (!reply.ok)
              _liveKey = "";
            callback?.(reply.ok, reply.rows);
          });
  }

  function publish(request, callback) {
    request.action = "publish";
    request.store = request.notification ? _store : null;
    if (request.notification)
      _pending[request.key] = true;
    _send(request, callback);
  }

  function clearLegacyRepresentations(callback) {
    _send({
            action: "clear-legacy"
          }, callback);
  }

  function ensureStage(callback) {
    if (stageDirectory) {
      callback?.(true);
      return;
    }
    _send({
            action: "prepare"
          }, callback ? reply => callback(reply.ok) : undefined);
  }

  function release(key) {
    if (_pending[key]) {
      delete _pending[key];
      _history(false);
    }
  }

  function discard(directory, leaf) {
    if (directory && directory === stageDirectory)
      _send({
              action: "discard",
              stage: leaf
            });
  }

  function _send(packet, callback) {
    packet.id = ++_sequence;
    if (callback)
      _waiting[packet.id] = callback;
    if (stageDirectory) {
      storage.write(JSON.stringify(packet) + "\n");
    } else {
      _commands.push(packet);
      if (!retry.running)
        _start();
    }
  }

  function _receive(line) {
    const packet = JSON.parse(line);
    if (packet.stage) {
      stageDirectory = packet.stage;
      healthy.start();
      for (const queued of _commands)
        storage.write(JSON.stringify(queued) + "\n");
      _commands = [];
      return;
    }
    const callback = _waiting[packet.id];
    delete _waiting[packet.id];
    callback?.(packet);
  }

  function _start() {
    if (!storage.running) {
      _starting = true;
      storage.running = true;
    }
  }

  function _failed() {
    healthy.stop();
    stageDirectory = "";
    _commands = [];
    const waiting = _waiting;
    _waiting = ({});
    retry.interval = _retryDelay;
    _retryDelay = Math.min(_retryDelay * 2, 5000);
    retry.restart();
    for (const callback of Object.values(waiting))
      callback({
                 ok: false,
                 code: "retention-unavailable",
                 reason: "The image original store stopped"
               });
  }

  Timer {
    id: retry
    onTriggered: root._start()
  }
  Timer {
    id: healthy
    interval: 5000
    onTriggered: root._retryDelay = 100
  }

  Process {
    id: storage
    workingDirectory: Quickshell.shellDir + "/Scripts/python/src"
    command: ["python3", "-B", "-u", "-m", "images.retention", Settings.cacheDir]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: line => root._receive(line)
    }
    onStarted: root._starting = false
    onRunningChanged: {
      if (!running && root._starting) {
        root._starting = false;
        root._failed();
      }
    }
    onExited: root._failed()
  }
  Component.onDestruction: storage.stdinEnabled = false
}
