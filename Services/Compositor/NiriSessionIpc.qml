import Niri 1.0
import QtQuick
import "../../Helpers/NiriReply.js" as NiriReply
import qs.Commons

Item {
  id: root
  readonly property bool stateApiAvailable: typeof NiriState !== "undefined" && typeof NiriState.initialStateReceived === "boolean" && typeof NiriState.windowsSnapshot === "function"
  property int peerPid: -1
  property var _pendingReplies: new Map()
  property var _retireHandoff: null

  // Successful action reply = accepted handoff, not independent observation
  // that this exact configuration was applied. Never replay on reconnect.
  function activate(path, onComplete) {
    if (!stateApiAvailable || peerPid < 1 || _retireHandoff) {
      if (typeof onComplete === "function")
        onComplete(false, _retireHandoff ? "A niri handoff is already pending" : "Current niri peer credentials are unavailable");
      return;
    }
    var terminal = false;
    function finish(success, error) {
      if (terminal)
        return;
      terminal = true;
      root._retireHandoff = null;
      if (success)
        Logger.i("NiriSessionIpc", "niri accepted configuration handoff:", path);
      else
        Logger.e("NiriSessionIpc", "niri handoff failed/unknown:", error);
      if (typeof onComplete === "function")
        onComplete(success, error || "");
    }
    root._retireHandoff = function () {
      NiriReply.cancel(root._pendingReplies);
      finish(false, "The niri peer retired before configuration handoff settled");
    };
    try {
      var reply = NiriActions.sendAction({
                                           "LoadConfigFile": {
                                             "path": path
                                           }
                                         });
      if (!NiriReply.observe(root._pendingReplies, reply, result => finish(!result.isError, result.isError ? result.error.message : "")))
        finish(false, "Could not construct niri handoff reply");
    } catch (error) {
      finish(false, "niri handoff construction/transport failed");
    }
  }

  function readPeerPid() {
    const info = stateApiAvailable && NiriConnection.isConnected ? NiriConnection.peerInfo : null;
    const pid = info && info.credentialsAvailable && info.pid > 0 ? info.pid : -1;
    if (root.peerPid === pid)
      return;
    root.peerPid = pid;
    if (root._retireHandoff)
      root._retireHandoff();
  }
  Connections {
    target: root.stateApiAvailable ? NiriConnection : null
    function onConnectedChanged() {
      root.readPeerPid();
    }
    function onPeerInfoChanged() {
      root.readPeerPid();
    }
  }
  Connections {
    target: root.stateApiAvailable ? NiriEvents : null
    function onConfigLoaded(failed) {
      if (failed)
        Logger.e("NiriReload", "niri reported a generic configuration reload failure; not correlated to a bindings request");
    }
  }
  Component.onCompleted: root.readPeerPid()
  Component.onDestruction: NiriReply.cancel(_pendingReplies)
}
