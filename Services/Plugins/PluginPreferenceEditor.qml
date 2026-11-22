import QtQuick
import qs.Commons

// UI lifetime around a real draft/overlay. All admission, merge/difference,
// revision fences and persistence remain on the native handle's worker.
QtObject {
  id: root
  property var handle: null
  property var inputScope: null
  property var ownerCurrent: null
  // Optional field-intent capture. Legacy callers are unchanged until the
  // selected settings session requests this additional read-only metadata.
  property var fieldCapture: null
  required property var fields
  property bool writable: true
  property bool closed: false
  property bool _releasePending: false
  // A failed Apply stays admitted in the native store for Retry, so its
  // values are what every reader shows until it is retried or abandoned.
  property bool _failedApply: false
  property string openError: ""
  property var _initial: ({})
  property var _lifetime: ({
                             alive: true
                           })
  property var cancelOpen: null
  readonly property string error: openError || (handle ? handle.error || "" : "")
  readonly property bool ready: !closed && !!handle && handle.ready === true
  readonly property bool busy: !!handle && handle.busy === true
  readonly property bool dirty: !!handle && handle.dirty === true
  readonly property var values: handle ? handle.values : null
  readonly property var previewValues: handle ? (handle.preview || handle.values) : null
  readonly property var initialValue: _initial
  signal rebased(var result)
  onBusyChanged: {
    if (!busy && _releasePending)
      Qt.callLater(root._releaseWhenIdle);
  }

  // A destroyed presentation cannot own the final busy-editor cleanup.
  // Keep the release request with the editor through native settlement.
  function release() {
    _releasePending = true;
    Qt.callLater(root._releaseWhenIdle);
  }
  function _releaseWhenIdle() {
    // Losing the presentation is not an explicit Discard: it never abandons.
    if (_releasePending && !closed && !busy)
      _detach();
  }

  function copyValue(value) {
    return Settings.store.copyValue(value);
  }

  function previewScope() {
    return handle && typeof handle.previewScope === "function" ? handle.previewScope([]) : null;
  }

  function snapshot(source) {
    var input = source || values;
    var result = Object.create(null);
    for (var key of fields) {
      var value = input[key];
      if (value !== undefined)
        result[key] = Settings.store.copyValue(value);
    }
    return result;
  }
  function attach(nativeHandle) {
    if (closed) {
      nativeHandle.detach();
      return;
    }
    _initial = snapshot(nativeHandle.values);
    handle = nativeHandle;
  }
  // Opening is asynchronous for overlays. One terminal opening observation,
  // including refusal, is delivered outside the caller's construction stack.
  function whenReady(callback) {
    var active = true;
    var lifetime = _lifetime;
    function changed() {
      Qt.callLater(attempt);
    }
    function disconnect() {
      root.readyChanged.disconnect(changed);
      root.errorChanged.disconnect(changed);
      root.closedChanged.disconnect(changed);
    }
    function attempt() {
      if (!active || !lifetime.alive)
        return;
      if (!root.ready && !root.error && !root.closed)
        return;
      active = false;
      disconnect();
      var available = root.ready && (!root.ownerCurrent || root.ownerCurrent());
      callback(available ? {
                             status: "opened"
                           } : {
                 status: "failed",
                 refreshState: "not_refreshed",
                 error: {
                   code: root.error || (root.ready ? "editor-owner" : "editor-closed")
                 }
               });
    }
    readyChanged.connect(changed);
    errorChanged.connect(changed);
    closedChanged.connect(changed);
    Qt.callLater(attempt);
    return function () {
      if (active && lifetime.alive) {
        active = false;
        disconnect();
      }
    };
  }
  function refuse(callback, code) {
    var lifetime = _lifetime;
    Qt.callLater(function () {
      if (lifetime.alive && typeof callback === "function")
        callback({
                   status: "failed",
                   refreshState: "not_refreshed",
                   error: {
                     code: code
                   }
                 });
    });
    return false;
  }
  function apply(value, callback) {
    if (ownerCurrent && !ownerCurrent())
      return refuse(callback, "editor-owner");
    if (!writable)
      return refuse(callback, "editor-read-only");
    if (closed || _releasePending || !ready || busy || value !== values)
      return refuse(callback, "editor-state");
    var lifetime = _lifetime;
    return handle.apply(function (result) {
      if (!lifetime.alive || root.closed)
        return;
      var success = result.status === "saved" || result.status === "nothing_to_save";
      root._failedApply = result.status === "failed";
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
        if (refresh === "current")
          root._initial = root.snapshot();
        root.rebased({
                       refreshState: refresh
                     });
      }
      // The native callback owns a fresh snapshot; keep its other fields lazy.
      result.refreshState = refresh;
      if (!root._releasePending && typeof callback === "function")
        callback(result);
    });
  }
  function resetOverrides(callback) {
    if (ownerCurrent && !ownerCurrent())
      return refuse(callback, "editor-owner");
    if (!writable)
      return refuse(callback, "editor-read-only");
    if (_releasePending || !ready || busy)
      return refuse(callback, "editor-state");
    var lifetime = _lifetime;
    return handle.resetOverrides(function (result) {
      if (!lifetime.alive || root.closed)
        return;
      if (result.refreshState === "current" && result.status !== "failed")
        root._initial = root.snapshot();
      if (!root._releasePending && typeof callback === "function")
        callback(result);
    });
  }
  function discard() {
    if (busy)
      return false;
    var nativeHandle = handle;
    if (nativeHandle && _failedApply && typeof nativeHandle.abandonApply === "function") {
      // Discard after a failed Apply returns every reader to the saved values:
      // abandon exactly that admitted Apply, then drop the staged edits. The
      // native draft stays alive until its single result.
      _failedApply = false;
      _cancelOpening();
      closed = true;
      nativeHandle.abandonApply(function (result) {
        if (result.status !== "abandoned" && result.error?.code !== "apply-not-pending")
          Logger.w("PluginPreferenceEditor", "Discard could not abandon the failed Apply:", result.error?.code || result.status);
        nativeHandle.detach();
      });
      return true;
    }
    _detach();
    return true;
  }
  function _cancelOpening() {
    if (cancelOpen) {
      cancelOpen();
      cancelOpen = null;
    }
  }
  function _detach() {
    _cancelOpening();
    if (handle)
      handle.detach();
    closed = true;
  }
  Component.onDestruction: {
    _lifetime.alive = false;
    if (cancelOpen)
      cancelOpen();
    if (handle && !closed)
      handle.detach();
  }
}
