import QtQuick
import "../../../../Helpers/AdvancedMath.js" as AdvancedMath
import qs.Commons

Item {
  property var launcher: null
  property string name: I18n.tr("plugins.calculator")
  property string iconMode: Settings.data.appLauncher.iconMode

  function handleCommand(query) {
    // Handle >calc command or direct math expressions after >
    return query.startsWith(">calc") || (query.startsWith(">") && query.length > 1 && isMathExpression(query.substring(1)));
  }

  function getInlineResult(query) {
    if (!Settings.data.appLauncher.inlineCalculator) {
      return null;
    }

    if (query.startsWith(">")) {
      return null;
    }

    if (!isMathExpression(query)) {
      return null;
    }


    try {
      let result = AdvancedMath.evaluate(query.trim());
      return {
        "name": AdvancedMath.formatResult(result),
        "description": `${query} = ${result}`,
        "icon": iconMode === "tabler" ? "calculator" : "accessories-calculator",
        "isTablerIcon": true,
        "isImage": false,
        "isCalculatorResult": true,
        "onActivate": function () {
          // TODO: copy entry to clipboard via ClipHist
          launcher.close();
        }
      };
    } catch (error) {
      return null;
    }
  }

  function commands() {
    return [
          {
            "name": ">calc",
            "description": I18n.tr("plugins.calculator-description"),
            "icon": iconMode === "tabler" ? "calculator" : "accessories-calculator",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(">calc ");
            }
          }
        ];
  }

  function getResults(query) {
    let expression = "";

    if (query.startsWith(">calc")) {
      expression = query.substring(5).trim();
    } else if (query.startsWith(">")) {
      expression = query.substring(1).trim();
    } else {
      return [];
    }

    if (!expression) {
      return [
            {
              "name": I18n.tr("plugins.calculator-name"),
              "description": I18n.tr("plugins.calculator-enter-expression"),
              "icon": iconMode === "tabler" ? "calculator" : "accessories-calculator",
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

  function isMathExpression(expr) {
    // Check if string looks like a math expression
    // Allow: digits, operators, parentheses, decimal points, whitespace, letters (for functions), commas
    if (!/^[\d\s\+\-\*\/\(\)\.\%\^a-zA-Z,]+$/.test(expr)) {
      return false;
    }

    // Must contain at least one operator OR a function call (letter followed by parenthesis)
    if (!/[+\-*/%\^]/.test(expr) && !/[a-zA-Z]\s*\(/.test(expr)) {
      return false;
    }
    
    // Reject if ends with an operator (incomplete expression)
    if (/[+\-*/%\^]\s*$/.test(expr)) {
      return false;
    }
    
    // Reject if it's just letters (would match app names)
    if (/^[a-zA-Z\s]+$/.test(expr)) {
      return false;
    }
    
    return true;
  }
}
