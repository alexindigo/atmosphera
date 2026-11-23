import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Private protocol/lifetime part of ImageCacheService. A subscription is an
// interest, not a process: identical representations share one two-slot worker.
Scope {
  id: root
  readonly property bool running: process.running
  readonly property int interestCount: Object.keys(_tokens).length
  readonly property int requestCount: Object.keys(_entries).length
  readonly property var statistics: _statistics
  property var _entries: ({})
  property var _tokens: ({})
  property var _statistics: ({})
  property var _clears: []
  property int _sequence: 0
  property bool _ready: false
  property bool _started: false
  property bool _armed: false
  property bool _closing: false
  property var _notificationStore: null
  property var _notificationLive: null
  property string _notificationLiveKey: ""
  property var _notificationQueue: []
  property var _notificationFlight: null
  property string _notificationBatch: ""
  signal activity(var event)

  function openNotificationHistory(directory, history, callback) {
    _notificationStore = {
      directory: directory,
      history: history
    };
    _notificationQueue = [..._notificationQueue,
                          {
                            load: true,
                            callback: callback
                          }
        ];
    flush.restart();
  }

  function updateNotificationHolders(paths, rows, callback) {
    const key = JSON.stringify(paths);
    if (key !== _notificationLiveKey) {
      _notificationLiveKey = key;
      _notificationLive = paths;
    }
    if (rows !== undefined)
      _notificationQueue = [..._notificationQueue.filter(command => !command.rows),
                            {
                              rows: rows,
                              callback: callback
                            }
          ];
    if (_notificationLive !== null || rows !== undefined)
      flush.restart();
  }

  function _settleNotifications(reply) {
    const flight = _notificationFlight;
    if (!flight || flight.id !== reply.id)
      return false;
    _notificationFlight = null;
    if (!reply.ok)
      _notificationLiveKey = "";
    flight.callback?.(reply.ok, reply.rows);
    flush.restart();
    return true;
  }

  function acquire(request, callback) {
    // Canonical field order also prevents unrelated caller properties from
    // changing coalescing, and keeps every representation/revision distinct.
    var spec = {
      source: String(request.source),
      revision: String(request.revision || ""),
      width: request.width,
      height: request.height,
      fit: request.fit || "contain",
      roundedRadius: request.roundedRadius || 0,
      animationIntent: request.animationIntent || "still",
      operation: request.operation || "render",
      destinationDirectory: String(request.destinationDirectory || ""),
      notification: request.notification === true,
      retry: !!request.retry
    };
    var key = JSON.stringify(spec);
    var token = String(++_sequence);
    var entry = _entries[key];
    if (!entry) {
      entry = {
        request: Object.assign({
                                 id: token,
                                 generation: _sequence
                               }, spec),
        listeners: {},
        result: null
      };
      _entries[key] = entry;
    }
    entry.listeners[token] = callback;
    _tokens = Object.assign({}, _tokens, {
                              [token]: key
                            });
    _entries = Object.assign({}, _entries);
    if (entry.result) {
      Qt.callLater(function () {
        if (root._tokens[token] === key && root._entries[key] === entry)
          callback(entry.result);
      });
    }
    flush.restart();
    return token;
  }

  // Observation only: the source of every live interest, in token order.
  function interestSources() {
    return Object.values(_tokens).map(key => _entries[key].request.source);
  }

  function release(token) {
    var key = _tokens[token];
    var entry = _entries[key];
    if (!entry)
      return;
    delete entry.listeners[token];
    var tokens = Object.assign({}, _tokens);
    delete tokens[token];
    _tokens = tokens;
    if (Object.keys(entry.listeners).length === 0) {
      var entries = Object.assign({}, _entries);
      delete entries[key];
      _entries = entries;
    }
    flush.restart();
  }

  // Owner-scoped clear. The worker leases every held representation, so a
  // consumer that still holds an interest (in any shell/lock process) keeps
  // its file; everything else in the private namespace is removed.
  function clear(legacy, callback) {
    _clears = _clears.concat([
                               {
                                 id: "clear-" + (++_sequence),
                                 legacy: legacy,
                                 callback: callback,
                                 sent: false
                               }
                             ]);
    flush.restart();
  }

  function _settleClear(id, result) {
    var clear = _clears.find(item => item.id === id);
    if (!clear)
      return false;
    _clears = _clears.filter(item => item !== clear);
    if (typeof clear.callback === "function")
      clear.callback(result);
    flush.restart();
    return true;
  }

  function _fail(code, reason) {
    _ready = false;
    const flight = _notificationFlight;
    const queued = _notificationQueue;
    _notificationFlight = null;
    _notificationQueue = [];
    _notificationLiveKey = "";
    flight?.callback?.(false, null);
    for (const command of queued)
      command.callback?.(false, null);
    for (var clear of _clears.slice())
      _settleClear(clear.id, {
                     ok: false,
                     code: code,
                     reason: reason
                   });
    for (var entry of Object.values(_entries)) {
      if (entry.result)
        continue;
      entry.result = {
        status: "unavailable",
        url: "",
        code: code,
        reason: reason
      };
      for (var callback of Object.values(entry.listeners))
        callback(entry.result);
    }
    Logger.e("ImageCache", reason);
    _closing = true;
    process.stdinEnabled = false;
  }

  function _receive(line) {
    var reply;
    try {
      reply = JSON.parse(line);
      if (!reply || typeof reply !== "object" || Array.isArray(reply))
        throw new Error("Invalid reply");
    } catch (error) {
      _fail("worker-protocol", "The image worker returned an invalid message");
      return;
    }
    if (reply.event === "ready") {
      _ready = true;
      flush.restart();
      return;
    }
    if (reply.event === "protocol-error") {
      _fail("worker-protocol", "The image worker rejected its request message");
      return;
    }
    if (reply.event === "notification-sync") {
      if (typeof reply.ok !== "boolean" || !_settleNotifications(reply))
        _fail("worker-protocol", "The image worker returned an unknown notification result");
      return;
    }
    if (reply.event === "cleared" || reply.event === "clear-failed") {
      var cleared = reply.event === "cleared";
      if (!(typeof reply.id === "string" && (cleared ? ["removed", "kept", "refused"].every(field => Number.isInteger(reply[field]) && reply[field] >= 0) : typeof reply.reason === "string"))) {
        _fail("worker-protocol", "The image worker returned an invalid clear result");
        return;
      }
      activity(reply);
      if (!_settleClear(reply.id, cleared ? {
                                              ok: true,
                                              removed: reply.removed,
                                              kept: reply.kept,
                                              refused: reply.refused
                                            } : {
                          ok: false,
                          code: reply.code,
                          reason: reply.reason
                        }))
        _fail("worker-protocol", "The image worker returned an unknown clear result");
      return;
    }
    var event = reply.event || reply.status;
    activity(reply);
    var stats = Object.assign({}, _statistics);
    stats[event] = (stats[event] || 0) + 1;
    _statistics = stats;
    if (!reply.status) {
      if (!["command", "command-result", "cancelled", "ffmpeg"].includes(reply.event))
        _fail("worker-protocol", "The image worker returned an unknown message");
      return;
    }
    if (typeof reply.id !== "string" || !Number.isInteger(reply.generation)) {
      _fail("worker-protocol", "The image worker returned an invalid request identity");
      return;
    }
    var entry = Object.values(_entries).find(item => item.request.id === reply.id && item.request.generation === reply.generation);
    if (!entry || entry.result)
      return;
    var request = entry.request;
    // Output dimensions are distinct from the requested bounding box; inspect
    // reports original dimensions, while normalized output must fit that box.
    var rendered = ["hit", "generated"].includes(reply.status);
    if (rendered && request.operation === "retain" && (typeof reply.originalPath !== "string" || !reply.originalPath.startsWith("/") || typeof reply.contentSha256 !== "string" || !/^[a-f0-9]{64}$/.test(reply.contentSha256))) {
      _fail("worker-protocol", "The image worker returned an invalid retained source");
      return;
    }
    if (!["hit", "generated", "inspected", "unavailable"].includes(reply.status) || reply.animationIntent !== request.animationIntent || typeof reply.url !== "string" || (reply.status !== "unavailable" && (!Number.isInteger(reply.width) || !Number.isInteger(reply.height) || reply.width < 1 || reply.height < 1 || !Number.isInteger(reply.frames)
                                                                                                                                                                                                              || reply.frames < 1)) || (rendered && (!reply.url.startsWith("file://") || reply.width > request.width || reply.height > request.height)) || (
          reply.status === "inspected" && reply.url !== "") || (reply.status === "unavailable" && (reply.url !== "" || typeof reply.code !== "string" || typeof reply.reason !== "string"))) {
      _fail("worker-protocol", "The image worker returned an invalid result");
      return;
    }
    entry.result = reply;
    for (var callback of Object.values(entry.listeners))
      callback(reply);
    flush.restart();
  }

  function _sync() {
    const notificationWork = _notificationStore && (_notificationLive !== null || _notificationQueue.length);
    if (!process.running) {
      if (!interestCount && !_clears.length && !notificationWork)
        return;
      if (!_clears.length && !notificationWork && !Object.values(_entries).some(entry => !entry.result))
        return;
      _ready = false;
      _started = false;
      _closing = false;
      process.stdinEnabled = true;
      _armed = true;
      process.running = true;
    }
    if (_ready && !_closing) {
      // A settled, held representation stays leased by the worker (also after
      // a worker restart) without re-running its request.
      var batch = [];
      for (var entry of Object.values(_entries)) {
        if (!entry.result)
          batch.push(entry.request);
        else if (["hit", "generated"].includes(entry.result.status))
          batch.push({
                       id: entry.request.id,
                       generation: entry.request.generation,
                       notification: entry.request.notification,
                       lease: entry.result.url
                     });
      }
      if (_notificationStore) {
        if (_notificationFlight)
          return;
        const batchKey = JSON.stringify(batch);
        if (notificationWork || batchKey !== _notificationBatch) {
          const command = _notificationQueue[0];
          _notificationQueue = _notificationQueue.slice(1);
          const id = String(++_sequence);
          _notificationFlight = {
            id: id,
            callback: command?.callback
          };
          const message = Object.assign({
                                          command: "notification-sync",
                                          id: id,
                                          interests: batch
                                        }, _notificationStore);
          if (_notificationLive !== null)
            message.live = _notificationLive;
          if (command?.load)
            message.load = true;
          if (command?.rows !== undefined)
            message.rows = command.rows();
          _notificationLive = null;
          _notificationBatch = batchKey;
          process.write(JSON.stringify(message) + "\n");
          return;
        }
      } else {
        process.write(JSON.stringify(batch) + "\n");
      }
      // Interest changes first: a release that preceded clear() is honored.
      for (var clear of _clears.filter(item => !item.sent)) {
        clear.sent = true;
        process.write(JSON.stringify({
                                       command: "clear",
                                       id: clear.id,
                                       legacy: clear.legacy
                                     }) + "\n");
      }
      if (!interestCount && !_clears.length) {
        _closing = true;
        process.stdinEnabled = false;
      }
    }
  }

  Process {
    id: process
    command: ["python3", "-B", "-u", Quickshell.shellDir + "/Scripts/python/image-worker.py"]
    stdout: SplitParser {
      onRead: data => root._receive(data)
    }
    // Never retain unbounded decoder logs or echo source URLs/data. The worker
    // streams command diagnostics privately and emits structured error codes.
    stderr: SplitParser {
      onRead: data => Logger.d("ImageCache", "Image worker diagnostic")
    }
    onStarted: root._started = true
    onRunningChanged: {
      if (root._armed && !root._started && !running) {
        root._armed = false;
        root._fail("worker-start", "The image worker could not start");
      }
    }
    onExited: (code, status) => {
      root._armed = false;
      root._ready = false;
      root._notificationBatch = "";
      if (!root._closing || code !== 0 || status !== 0)
        root._fail("worker-exit", "The image worker exited before completing its requests");
      root._closing = false;
      flush.restart();
    }
  }
  Timer {
    id: flush
    interval: 0
    onTriggered: root._sync()
  }
  Component.onDestruction: process.stdinEnabled = false
}
