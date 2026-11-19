import QtQuick
import "../Helpers/OwnedProcess.js" as OwnedProcess
import qs.Commons

// Prepare directory scaffolding before loading the graph that constructs file
// owners. No preference files, settings values or persistence receipts here.
QtObject {
  id: root
  property bool ready: false
  Component.onCompleted: OwnedProcess.run(root, ["mkdir", "-p", "--", SettingsPaths.configDir, SettingsPaths.overridesDir, SettingsPaths.overridesDir + "plugins", SettingsPaths.cacheDir], null, function (result) {
    if (!result.success) {
      console.error("Settings directory bootstrap failed");
      Qt.exit(2);
      return;
    }
    root.ready = true;
  })
}
