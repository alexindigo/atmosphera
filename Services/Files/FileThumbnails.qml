import QtQuick
import Quickshell
import qs.Services.UI

// Per-picker viewport admission only. Interests share ImageCacheService's single
// worker with images and other pickers; retiring one picker cannot close it.
Scope {
  id: root
  property bool enabled: true
  readonly property var urls: _urls
  readonly property var results: _results
  readonly property var statistics: _statistics
  readonly property bool running: Object.keys(_subscriptions).length > 0 && ImageCacheService.sourceWorkerRunning
  property var _urls: ({})
  property var _results: ({})
  property var _interests: ({})
  property var _subscriptions: ({})
  property var _statistics: ({
                               ffmpeg: 0,
                               hit: 0,
                               generated: 0,
                               failed: 0,
                               cancelled: 0
                             })
  property int _nextToken: 0
  property var _lifetime: ({
                             alive: true
                           })

  function acquire() {
    return ++_nextToken;
  }
  function update(token, path, pixels, stamp) {
    var next = Object.assign({}, _interests);
    if (path)
      next[token] = {
        path: path,
        pixels: pixels,
        stamp: stamp
      };
    else
    delete next[token];
    _interests = next;
    flush.restart();
  }
  function release(token) {
    update(token, "", 0, "");
  }
  function _requests() {
    var paths = {};
    for (var item of Object.values(_interests)) {
      if (!paths[item.path] || item.pixels > paths[item.path].pixels)
        paths[item.path] = item;
    }
    return enabled ? paths : {};
  }
  function _count(event) {
    var stats = Object.assign({}, _statistics);
    stats[event] = (stats[event] || 0) + 1;
    _statistics = stats;
  }
  function _subscribe(item) {
    var entry = {
      request: item,
      token: "",
      result: null
    };
    _subscriptions[item.path] = entry;
    var lifetime = _lifetime;
    // Match the existing physical-pixel freedesktop bucket policy. Geometry
    // changes within a bucket still carry the exact interest identity below.
    var pixels = item.pixels <= 128 ? 128 : item.pixels <= 256 ? 256 : item.pixels <= 512 ? 512 : 1024;
    entry.token = ImageCacheService.acquireSource({
                                                    source: item.path,
                                                    revision: String(item.stamp),
                                                    width: pixels,
                                                    height: pixels,
                                                    fit: "contain",
                                                    animationIntent: "still",
                                                    operation: "video-thumbnail"
                                                  }, function (reply) {
                                                    if (!lifetime.alive || root._subscriptions[item.path] !== entry)
                                                      return;
                                                    entry.result = reply;
                                                    root._count(reply.status === "unavailable" ? "failed" : reply.status);
                                                    root._publish();
                                                  });
  }
  function _publish() {
    var urls = {}, results = {};
    for (var path of Object.keys(_subscriptions)) {
      var reply = _subscriptions[path].result;
      if (reply) {
        urls[path] = reply.url;
        results[path] = reply;
      }
    }
    _urls = urls;
    _results = results;
  }
  function _sync() {
    var requests = _requests();
    for (var path of Object.keys(_subscriptions)) {
      var entry = _subscriptions[path];
      var next = requests[path];
      if (!next || next.stamp !== entry.request.stamp || next.pixels !== entry.request.pixels) {
        if (!entry.result)
          _count("cancelled");
        ImageCacheService.releaseSource(entry.token);
        delete _subscriptions[path];
      }
    }
    for (var item of Object.values(requests)) {
      if (!_subscriptions[item.path])
        _subscribe(item);
    }
    _subscriptions = Object.assign({}, _subscriptions);
    _publish();
  }
  Connections {
    target: ImageCacheService
    function onSourceEvent(event) {
      if (event.event === "video-frame-request" && root._subscriptions[event.path])
        root._count("videoFrame");
    }
  }
  Timer {
    id: flush
    interval: 0
    onTriggered: root._sync()
  }
  onEnabledChanged: flush.restart()
  Component.onDestruction: {
    _lifetime.alive = false;
    flush.stop();
    for (var entry of Object.values(_subscriptions))
      ImageCacheService.releaseSource(entry.token);
  }
}
