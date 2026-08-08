import QtQuick
import Niri 1.0
import qs.Commons

// niriqml-backed IPC helper for NiriSessionInit. Kept in a separate file
// loaded via Loader so systems without qt6-niriqml installed degrade to the
// `niri msg` CLI fallback instead of failing to load the singleton.
Item {
  id: root

  property int peerPid: -1

  function activate(path) {
    if (NiriConnection.isConnected) {
      _send(path);
    } else {
      _pendingPath = path;
    }
  }

  property string _pendingPath: ""

  function _readPeerPid() {
    try {
      var pi = NiriConnection.peerInfo;
      if (pi && pi.pid > 0)
        root.peerPid = pi.pid;
    } catch (e) {}
  }

  function _send(path) {
    try {
      var reply = NiriActions.sendAction({
                                           LoadConfigFile: {
                                             path: path
                                           }
                                         });
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriSessionIpc", "load-config-file failed:", reply.error.message);
        else
          Logger.i("NiriSessionIpc", "niri session config activated:", path);
      });
    } catch (e) {
      Logger.e("NiriSessionIpc", "sendAction failed:", e);
    }
  }

  Connections {
    target: NiriConnection
    function onConnectedChanged() {
      if (NiriConnection.isConnected) {
        root._readPeerPid();
        if (root._pendingPath !== "") {
          var p = root._pendingPath;
          root._pendingPath = "";
          root._send(p);
        }
      }
    }
  }

  Component.onCompleted: root._readPeerPid()
}
