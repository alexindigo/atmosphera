// niriqml LoadConfigFile harness (plan: post-071-settings-icons-release-notes).
// Loads a niri config through the shell's established typed niriqml
// integration (NiriActions.sendAction LoadConfigFile) — never CLI wiring.
// Prints NIRI_LOAD|OK|<path> / NIRI_LOAD|ERROR|<msg> / NIRI_LOAD|TIMEOUT.
import QtQuick
import Quickshell
import Niri 1.0

Item {
  id: root

  readonly property string targetPath: Quickshell.env("NIRI_LOAD_CONFIG") || ""
  property bool _sent: false

  Component.onCompleted: {
    console.log("NIRI_LOAD|START|" + targetPath);
    if (targetPath === "") {
      console.log("NIRI_LOAD|ERROR|empty path");
      Qt.exit(1);
    }
    if (NiriConnection.isConnected)
      send();
  }

  Connections {
    target: NiriConnection
    function onConnectedChanged() {
      if (NiriConnection.isConnected)
        root.send();
    }
  }

  function send() {
    if (_sent)
      return;
    _sent = true;
    try {
      var reply = NiriActions.sendAction({
                                           LoadConfigFile: {
                                             path: targetPath
                                           }
                                         });
      reply.finished.connect(function () {
        if (reply.isError) {
          console.log("NIRI_LOAD|ERROR|" + reply.error.message);
          Qt.exit(1);
        } else {
          console.log("NIRI_LOAD|OK|" + targetPath);
          Qt.exit(0);
        }
      });
    } catch (e) {
      console.log("NIRI_LOAD|ERROR|" + e);
      Qt.exit(1);
    }
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.log("NIRI_LOAD|TIMEOUT");
      Qt.exit(2);
    }
  }
}
