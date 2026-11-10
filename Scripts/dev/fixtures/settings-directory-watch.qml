import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property int phase: 0
  property bool started: false
  property bool waiting: false
  readonly property string observed: Settings.data.ui.fontDefault
  readonly property var names: ["I4 Directory A", "I4 Directory B", "I4 Directory C", "I4 Directory D", "I4 Directory E", "I4 Directory F", "I4 Directory G"]

  function finish(code) {
    Qt.callLater(function () { Qt.exit(code); });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    if (observed !== names[0]) {
      console.error("I4_DIRECTORY_WATCH_ASSERT: initial consumer");
      finish(2);
      return;
    }
    advance();
  }
  function advance() {
    phase++;
    if (phase === names.length) {
      console.log("I4_DIRECTORY_WATCH: PASS");
      finish(0);
      return;
    }
    action.command = ["python3", Quickshell.env("I4_DIRECTORY_SWITCH"), Quickshell.env("ATMOSPHERA_CONFIG_DIR"), String(phase)];
    action.running = true;
  }
  Process {
    id: action
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: (code, status) => {
      if (code !== 0 || status !== 0) {
        console.error("I4_DIRECTORY_WATCH_ASSERT: action", phase);
        root.finish(2);
      } else {
        root.waiting = true;
      }
    }
  }
  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (root.waiting && root.observed === root.names[root.phase]) {
        console.log("I4_DIRECTORY_WATCH: OBSERVED", root.phase);
        root.waiting = false;
        root.advance();
      }
    }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("I4_DIRECTORY_WATCH_ASSERT: watchdog", root.phase, root.observed);
      root.finish(2);
    }
  }
}
