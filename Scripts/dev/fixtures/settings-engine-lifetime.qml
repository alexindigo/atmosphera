import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import AtmospheraSettingsTest 1.0

ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: probe
        property bool started: false
        property bool submitted: false
        property bool completed: false
        NativeStoreProbe { id: native; target: Settings.store }
        function check(ok, message) { if (!ok) throw new Error("ENGINE_LIFETIME_ASSERT: " + message); }
        function fail(error) { console.error(String(error)); Qt.exit(2); }
        function begin() {
          if (started || !Settings.isLoaded) return;
          started = true;
          try {
            console.log("ENGINE_LIFETIME: ENGINE_READY", Settings.data.ui.fontDefaultScale);
            if (Settings.data.ui.fontDefaultScale === 1.25) {
              Settings.store.close(function (result) {
                try {
                  probe.check(result.status === "nothing_to_save", "reloaded/cold settled close");
                  console.log("ENGINE_LIFETIME: CONSUMER_CLOSE_PASS"); Qt.exit(0);
                } catch (error) { probe.fail(error); }
              });
              return;
            }
            check(Quickshell.env("I5_ENGINE_COLD") !== "1", "cold saved consumer");
            check(Settings.data.ui.fontDefaultScale === 1, "initial consumer");
            Settings.data.ui.fontDefaultScale = 1.25;
            submitted = true;
            Settings.saveImmediate(function (result) {
              probe.completed = true;
              probe.check(result.status === "saved", "original save acknowledgement if delivered before detach");
              console.log("ENGINE_LIFETIME: ORIGINAL_SAVED");
            });
          } catch (error) { fail(error); }
        }
        IpcHandler {
          target: "engineLifetime"
          function reloadPending(): string {
            probe.check(probe.submitted && !probe.completed, "reload during outstanding save");
            var state = native.sample([["ui", "fontDefaultScale"]]);
            probe.check(state.pendingRequests.length > 0, "native save request remains pending");
            probe.check(Settings.data.ui.fontDefaultScale === 1.25, "pending effective consumer");
            console.log("ENGINE_LIFETIME: RELOAD_PENDING", JSON.stringify(state));
            Quickshell.reload(false);
            return "requested";
          }
        }
        Component.onCompleted: begin()
        Connections { target: Settings; function onSettingsLoaded() { probe.begin(); } }
        Timer { interval: 25000; running: true; onTriggered: probe.fail("watchdog") }
      }
    }
  }
}
