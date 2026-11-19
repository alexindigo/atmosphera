import QtQuick
import Quickshell
import ConfigQml 1.0
import qs.Commons as Main

// Minimal first-use parent-directory witness. No Settings singleton, plugin
// service, external writer, timers between capture/save, or GUI persistence.
ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_FIRST_USE_DIR")
  property bool started: false
  Main.SettingsSources {
    id: routes
    settingsFile: root.directory + "/settings.json"
    overridesDirectory: root.directory + "/settings"
  }
  ConfigStore {
    id: store
    autoSave: false
    schema: Main.SettingsSchema { homeDirectory: "/inert/home"; defaultFont: "Test Sans"; fixedFont: "Test Mono" }
    sources: routes.sources
    evidenceDirectory: root.directory + "/evidence"
    onStatusChanged: {
      if (ready) Qt.callLater(root.begin);
      else if (status === ConfigStore.Error) root.fail("initialization " + error);
    }
  }
  function fail(error) { console.error("I5_FIRST_USE_ASSERT: " + String(error)); Qt.exit(2); }
  function begin() {
    if (started || !store.ready) return;
    started = true;
    store.retainGroup({requestKey: "first-use", paths: [["general", "scaleRatio"], ["bar", "position"], ["wallpaper", "directory"]], edits: [
      {path: ["general", "scaleRatio"], present: true, value: 1.74},
      {path: ["bar", "position"], present: true, value: "left"},
      {path: ["wallpaper", "directory"], present: true, value: "/owner-wallpapers"}
    ], dependencies: []}, function (capture) {
      console.log("I5_FIRST_USE_CAPTURE: " + JSON.stringify(capture));
      if (capture.status !== "retained") { fail("capture " + capture.error?.code); return; }
      store.saveGroup(capture.groupToken, function (result) {
        console.log("I5_FIRST_USE_RECEIPT: " + JSON.stringify(result));
        if (result.status !== "saved") { fail("save " + result.error?.code); return; }
        if (store.values.general.scaleRatio !== 1.74 || store.values.bar.position !== "left" || store.values.wallpaper.directory !== "/owner-wallpapers") {
          fail("consumer"); return;
        }
        store.close(function (closed) {
          if (closed.status !== "nothing_to_save") { fail("close " + closed.error?.code); return; }
          console.log("I5_FIRST_USE: PASS");
          Qt.exit(0);
        });
      });
    });
  }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 25000; running: true; onTriggered: root.fail("timeout") }
}
