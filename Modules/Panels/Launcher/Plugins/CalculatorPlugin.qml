import QtQuick
import "../../../../Helpers/AdvancedMath.js" as AdvancedMath
import qs.Commons

// Legacy calculator plugin for >calc command
// TODO: Remove this plugin in 2-3 bussiness days
Item {
  property var launcher: null
  property string name: I18n.tr("plugins.calculator")
  property string iconMode: Settings.data.appLauncher.iconMode

  function handleCommand(query) {
    return query.startsWith(">calc");
  }

  function commands() {
    return [
          {
            "name": ">calc",
            "description": I18n.tr("plugins.calculator-deprecated"),
            "icon": "alert-triangle",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">calc ");
            }
          }
        ];
  }

  function getResults(query) {
    let expression = query.substring(5).trim();

    if (!expression) {
      return [
            {
              "name": I18n.tr("plugins.calculator-name"),
              "description": I18n.tr("plugins.calculator-deprecated"),
              "icon": "alert-triangle",
              "isTablerIcon": true,
              "isImage": false,
              "onActivate": function () {}
            }
          ];
    }

    try {
      let result = AdvancedMath.evaluate(expression.trim());

      return [
            {
              "name": AdvancedMath.formatResult(result),
              "description": `${expression} = ${result}`,
              "icon": iconMode === "tabler" ? "calculator" : "accessories-calculator",
              "isTablerIcon": true,
              "isImage": false,
              "onActivate": function () {
                // TODO: copy entry to clipboard via ClipHist
                launcher.close();
              }
            }
          ];
    } catch (error) {
      return [
            {
              "name": I18n.tr("plugins.calculator-error"),
              "description": error.message || "Invalid expression",
              "icon": iconMode === "tabler" ? "circle-x" : "dialog-error",
              "isTablerIcon": true,
              "isImage": false,
              "onActivate": function () {}
            }
          ];
    }
  }
}
