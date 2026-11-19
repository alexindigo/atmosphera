import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  SettingsBootstrap {
    id: bootstrap
  }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: probe
        property bool started: false
        function begin() {
          if (started || !Settings.isLoaded)
            return;
          started = true;
          Settings.data.ui.fontDefaultScale = 1.25;
          Settings.saveImmediate(function (result) {
            var failed = Quickshell.env("SCHEDULE_RELEASE") === "1";
            if (result.status !== (failed ? "failed" : "saved")) {
              console.error("SCHEDULE_ASSERT:", JSON.stringify(result));
              Qt.exit(2);
              return;
            }
            console.log("NATIVE_SCHEDULE: PASS", failed ? "failure" : "normal");
            Qt.exit(0);
          });
        }
        Component.onCompleted: begin()
        Connections {
          target: Settings
          function onSettingsLoaded() {
            probe.begin();
          }
        }
        Timer {
          interval: 20000
          running: true
          onTriggered: Qt.exit(2)
        }
      }
    }
  }
}
