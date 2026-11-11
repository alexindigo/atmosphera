import QtQuick
import Quickshell
import qs.Commons
import AtmospheraSettingsTest 1.0

ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: root
        property bool started: false
        property bool finished: false
        property int beats: 0
        NativeStoreProbe { id: observation; target: Settings.store }
        function check(ok, message) { if (!ok) throw new Error("NATIVE_IO_ASSERT: " + message); }
        function begin() {
          if (started || !Settings.isLoaded) return;
          started = true;
          if (Quickshell.env("NATIVE_IO_COLD") === "1") {
            check(Settings.data.ui.fontDefaultScale === 1.25, "cold actual consumer");
            console.log("NATIVE_IO: COLD_PASS"); Qt.exit(0); return;
          }
          Settings.data.ui.fontDefaultScale = 1.25;
          Settings.saveImmediate(function (result) {
            finished = true;
            check(result.status === "saved", "actual readback receipt");
            check(Settings.data.ui.fontDefaultScale === 1.25, "actual consumer after publication");
            const state = observation.sample([["ui", "fontDefaultScale"]]);
            check(state.paths["ui.fontDefaultScale"].latestInput !== "0" && state.inputs.length > 0, "actual native owner observed");
            check(beats >= 10, "GUI remained responsive while native worker was held");
            console.log("NATIVE_IO: SAVED_PASS"); Qt.exit(0);
          });
        }
        Component.onCompleted: begin()
        Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
        Timer {
          interval: 10; repeat: true; running: root.started && !root.finished
          onTriggered: {
            root.check(Settings.data.ui.fontDefaultScale === 1.25, "held-write consumer");
            if (++root.beats === 10) console.log("NATIVE_IO: HELD_GUI_PASS");
          }
        }
        Timer { interval: 20000; running: true; onTriggered: { console.error("NATIVE_IO_ASSERT: deadline"); Qt.exit(2); } }
      }
    }
  }
}
