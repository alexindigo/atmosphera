// VM driver pads the empty desktop section so its initial read completes last.
// Keep the save synchronous in settingsLoaded: the owner must defer its reload.
import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  property bool started: false
  readonly property var consumer: Settings.data.desktopWidgets.monitorWidgets

  function checkConsumer() {
    if (consumer.length !== 1 || consumer[0].name !== "reentry" || consumer[0].widgets[0].tag !== "persisted")
      throw new Error("I4_LOAD_REENTRY_ASSERT: consumer did not receive saved input");
  }

  function finish(code) {
    Qt.callLater(function () { Qt.exit(code); });
  }

  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    try {
      if (verifyOnly) {
        checkConsumer();
        console.log("I4_LOAD_REENTRY: RESTART_PASS");
        finish(0);
        return;
      }
      Settings.data.desktopWidgets.monitorWidgets = [{name: "reentry", widgets: [{id: "Clock", tag: "persisted"}]}];
      Settings.saveResult(function (result) {
        try {
          if (result.status !== "saved")
            throw new Error("I4_LOAD_REENTRY_ASSERT: persistence receipt");
          checkConsumer();
          console.log("I4_LOAD_REENTRY: SAVED_PASS");
          finish(0);
        } catch (error) { console.error(String(error)); finish(2); }
      });
    } catch (error) { console.error(String(error)); finish(2); }
  }

  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 3000; running: true; onTriggered: { console.error("I4_LOAD_REENTRY_ASSERT: watchdog"); root.finish(2); } }
}
