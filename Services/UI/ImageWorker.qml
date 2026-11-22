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
  property int _sequence: 0
  property bool _ready: false
  property bool _started: false
  property bool _armed: false
  property bool _closing: false
  signal activity(var event)

  function acquire(request, callback) {
    // Canonical field order also prevents unrelated caller properties from
    // changing coalescing, and keeps every representation/revision distinct.
    var spec = {
      source: String(request.source),
      revision: String(request.revision || ""),
      width: request.width,
      height: request.height,
      fit: request.fit || "contain",
      animationIntent: request.animationIntent || "still",
      operation: request.operation || "render",
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

  function _fail(code, reason) {
    _ready = false;
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
    if (!process.running) {
      if (!interestCount)
        return;
      if (!Object.values(_entries).some(entry => !entry.result))
        return;
      _ready = false;
      _started = false;
      _closing = false;
      process.stdinEnabled = true;
      _armed = true;
      process.running = true;
    }
    if (_ready && !_closing) {
      process.write(JSON.stringify(Object.values(_entries).filter(entry => !entry.result).map(entry => entry.request)) + "\n");
      if (!interestCount) {
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
