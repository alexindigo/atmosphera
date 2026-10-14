import QtQuick

Item {
  id: root

  property var pluginApi: null

  implicitWidth: 80
  implicitHeight: 40

  function fxLog(phase) {
    var names = ["screen", "widgetId", "section", "sectionWidgetIndex", "sectionWidgetsCount", "widgetSettings", "widgetData", "widgetIndex"];
    var ctx = {};
    for (var i = 0; i < names.length; i++) {
      var n = names[i];
      if (!(n in root))
        continue;
      var v = root[n];
      if (v === null || v === undefined)
        ctx[n] = null;
      else if (n === "screen")
        ctx[n] = v.name;
      else if (typeof v === "object")
        ctx[n] = "obj";
      else
        ctx[n] = v;
    }
    console.log("FX " + JSON.stringify({ "id": "fx-bare", "entry": "desktopWidget", "phase": phase, "ctx": ctx }));
  }

  Component.onCompleted: fxLog("completed")
}
