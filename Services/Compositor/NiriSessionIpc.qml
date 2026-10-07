import Niri 1.0
import QtQuick
import qs.Commons

Item {
  id: root
  property int peerPid: -1

  // Successful action reply = accepted handoff, not independent observation
  // that this exact configuration was applied. Never replay on reconnect.
  function activate(path, onComplete) {
    var terminal = false;
    function finish(success, error) {
      if (terminal) return;
      terminal = true;
      if (success) Logger.i("NiriSessionIpc", "niri accepted configuration handoff:", path);
      else Logger.e("NiriSessionIpc", "niri handoff failed/unknown:", error);
      if (typeof onComplete === "function") onComplete(success, error || "");
    }
    if (!NiriConnection.isConnected) {
      finish(false, "niri connection unavailable; handoff not attempted");
      return;
    }
    try {
      var reply = NiriActions.sendAction({ "LoadConfigFile": { "path": path } });
      if (!reply) { finish(false, "Could not construct niri handoff reply"); return; }
      function completed() {
        if (terminal) return;
        finish(!reply.isError, reply.isError ? reply.error.message : "");
      }
      reply.finished.connect(completed);
      if (reply.isError) completed(); // immediate errors can precede connection
    } catch (error) {
      finish(false, "niri handoff construction/transport failed");
    }
  }

  function readPeerPid() {
    var info = NiriConnection.peerInfo;
    if (info && info.pid > 0) root.peerPid = info.pid;
  }
  Connections {
    target: NiriConnection
    function onConnectedChanged() {
      if (NiriConnection.isConnected) root.readPeerPid();
    }
  }
  Connections {
    target: NiriEvents
    function onConfigLoaded(failed) {
      if (failed)
        Logger.e("NiriReload", "niri reported a generic configuration reload failure; not correlated to a bindings request");
    }
  }
  Component.onCompleted: root.readPeerPid()
}
