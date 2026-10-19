import QtQuick
import Quickshell
import qs.Commons
import "../../Helpers/OwnedProcess.js" as OwnedProcess

// Per picker: interest ownership, one streaming worker, URL state. Views only
// supply viewport geometry and bind to FileThumbnail's result.
Scope {
  id: root
  property bool enabled: true
  readonly property var urls: _urls
  readonly property var statistics: _statistics
  readonly property bool running: _process !== null
  property var _urls: ({})
  property var _interests: ({})
  property var _statistics: ({ffmpeg: 0, hit: 0, generated: 0, failed: 0, cancelled: 0})
  property var _process: null
  property bool _ready: false
  property int _nextToken: 0
  property int _offset: 0
  property string _buffer: ""
  property var _sentRequests: []

  function acquire() { return ++_nextToken; }
  function update(token, path, pixels, stamp) {
    var next = Object.assign({}, _interests);
    if (path)
      next[token] = {path: path, pixels: pixels, stamp: stamp};
    else
      delete next[token];
    _interests = next;
    flush.restart();
  }
  function release(token) { update(token, "", 0, ""); }
  function _requests() {
    var paths = {};
    for (var item of Object.values(_interests)) {
      if (!paths[item.path] || item.pixels > paths[item.path].pixels)
        paths[item.path] = item;
    }
    return enabled ? Object.values(paths) : [];
  }
  function _receive() {
    var text = String(_process.stdout.text);
    _buffer += text.slice(_offset);
    _offset = text.length;
    var lines = _buffer.split("\n");
    _buffer = lines.pop();
    for (var line of lines) {
      var reply = JSON.parse(line);
      if (reply.event === "ready") {
        _ready = true;
        _sync();
      } else {
        var key = reply.event || reply.status;
        var stats = Object.assign({}, _statistics);
        if (stats[key] !== undefined) {
          ++stats[key];
          _statistics = stats;
        }
        if (reply.status && _requests().some(item => item.path === reply.path && item.stamp === reply.stamp && item.pixels === reply.pixels)) {
          var urls = Object.assign({}, _urls);
          urls[reply.path] = reply.url;
          _urls = urls;
        }
      }
    }
  }
  function _sync() {
    var requests = _requests();
    var urls = {};
    for (var item of requests) {
      if (_sentRequests.some(old => old.path === item.path && old.stamp === item.stamp && old.pixels === item.pixels) && _urls[item.path] !== undefined)
        urls[item.path] = _urls[item.path];
    }
    _urls = urls;
    _sentRequests = requests;
    if (!_process && requests.length) {
      _offset = 0;
      _buffer = "";
      _process = OwnedProcess.run(root, ["python3", "-B", "-u", Quickshell.shellDir + "/Scripts/python/src/filechooser/thumbnails.py"], null, function(result) {
        root._process = null;
        root._ready = false;
        if (!result.success)
          Logger.e("FileThumbnails", "Thumbnail worker exited", result.stderr);
      });
      if (_process) {
        _process.stdinEnabled = true;
        _process.stdout.waitForEnd = false;
        _process.stdout.dataChanged.connect(_receive);
      }
    }
    if (_ready && _process) {
      _process.write(JSON.stringify(requests) + "\n");
      if (!enabled)
        _process.stdinEnabled = false;
    }
  }
  Timer { id: flush; interval: 0; onTriggered: root._sync() }
  onEnabledChanged: flush.restart()
  Component.onDestruction: {
    flush.stop();
    if (_process)
      _process.stdinEnabled = false;
  }
}
