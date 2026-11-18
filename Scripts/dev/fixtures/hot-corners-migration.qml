import QtQuick
import Quickshell
import "../../../Helpers/PluginProfileMigration.js" as Migration

// Runs PluginProfileMigration.planV6 over the cases in HOT_CORNERS_PLAN_CASES
// (a JSON object: name -> input) and prints one line per case. Loaded from a
// private tree by hot-corners-migration-regression.py.
Item {
  Timer {
    interval: 0
    running: true
    onTriggered: {
      try {
        const cases = JSON.parse(Quickshell.env("HOT_CORNERS_PLAN_CASES"));
        for (const name of Object.keys(cases))
          console.log("HOT_CORNERS_PLAN|" + name + "|" + JSON.stringify(Migration.planV6(cases[name])));
        console.log("HOT_CORNERS_PLAN_DONE");
      } catch (error) {
        console.error("HOT_CORNERS_PLAN_ERROR " + error);
      }
      Qt.quit();
    }
  }
}
