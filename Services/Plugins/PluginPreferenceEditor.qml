import QtQuick
import qs.Commons

// UI lifetime around a real draft/overlay. All admission, merge/difference,
// revision fences and persistence remain on the native handle's worker.
QtObject {
  id: root
  property var handle: null
  property var inputScope: null
  required property var fields
  property bool writable: true
  property bool closed: false
  property string openError: ""
  property var _initial: ({})
  property var _lifetime: ({alive: true})
  property var cancelOpen: null
  readonly property string error: openError || (handle ? handle.error || "" : "")
  readonly property bool ready: !closed && !!handle && handle.ready === true
  readonly property bool busy: !!handle && handle.busy === true
  readonly property bool dirty: !!handle && handle.dirty === true
  readonly property var values: handle ? handle.values : null
  readonly property var previewValues: handle ? (handle.preview || handle.values) : null
  readonly property var initialValue: _initial
  signal rebased(var result)

  function copyValue(value) { return Settings.store.copyValue(value); }

  function previewScope() {
    return handle && typeof handle.previewScope === "function" ? handle.previewScope([]) : null;
  }

  function snapshot(source) {
    var input = source || values;
    var result = Object.create(null);
    for (var key of fields) {
      var value = input[key];
      if (value !== undefined) result[key] = Settings.store.copyValue(value);
    }
    return result;
  }
  function attach(nativeHandle) {
    if (closed) { nativeHandle.detach(); return; }
    _initial = snapshot(nativeHandle.values);
    handle = nativeHandle;
  }
  // Opening is asynchronous for overlays. One terminal opening observation,
  // including refusal, is delivered outside the caller's construction stack.
  function whenReady(callback) {
    var active = true;
    var lifetime = _lifetime;
    function changed() { Qt.callLater(attempt); }
    function disconnect() {
      root.readyChanged.disconnect(changed);
      root.errorChanged.disconnect(changed);
      root.closedChanged.disconnect(changed);
    }
    function attempt() {
      if (!active || !lifetime.alive) return;
      if (!root.ready && !root.error && !root.closed) return;
      active = false;
      disconnect();
      callback(root.ready ? {status: "opened"} : {status: "failed", refreshState: "not_refreshed", error: {code: root.error || "editor-closed"}});
    }
    readyChanged.connect(changed);
    errorChanged.connect(changed);
    closedChanged.connect(changed);
    Qt.callLater(attempt);
    return function () { if (active && lifetime.alive) { active = false; disconnect(); } };
  }
  function refuse(callback, code) {
    var lifetime = _lifetime;
    Qt.callLater(function () {
      if (lifetime.alive && typeof callback === "function") callback({status: "failed", refreshState: "not_refreshed", error: {code: code}});
    });
    return false;
  }
  function apply(value, callback) {
    if (!writable) return refuse(callback, "editor-read-only");
    if (closed || !ready || busy || value !== values) return refuse(callback, "editor-state");
    var lifetime = _lifetime;
    return handle.apply(function (result) {
      if (!lifetime.alive || root.closed) return;
      var success = result.status === "saved" || result.status === "nothing_to_save";
      var refresh = result.refreshState;
      if (!refresh) {
        var current = success && root.inputScope && root.fields.every(function (key) {
          var input = root.inputScope.info([key]).latestInput;
          var prefix = result.inputPrefix;
          return input.length < prefix.length || (input.length === prefix.length && input <= prefix);
        });
        refresh = success ? (current ? "current" : "stale") : "not_refreshed";
      }
      if (success) {
        if (refresh === "current") root._initial = root.snapshot();
        root.rebased({refreshState: refresh});
      }
      if (typeof callback === "function") callback(Object.assign({}, result, {refreshState: refresh}));
    });
  }
  function resetOverrides(callback) {
    if (!writable) return refuse(callback, "editor-read-only");
    if (!ready || busy) return refuse(callback, "editor-state");
    var lifetime = _lifetime;
    return handle.resetOverrides(function (result) {
      if (!lifetime.alive || root.closed) return;
      if (result.refreshState === "current" && result.status !== "failed") root._initial = root.snapshot();
      if (typeof callback === "function") callback(result);
    });
  }
  function discard() {
    if (busy) return false;
    if (cancelOpen) { cancelOpen(); cancelOpen = null; }
    if (handle) handle.detach();
    closed = true;
    return true;
  }
  Component.onDestruction: {
    _lifetime.alive = false;
    if (cancelOpen) cancelOpen();
    if (handle && !closed) handle.detach();
  }
}
