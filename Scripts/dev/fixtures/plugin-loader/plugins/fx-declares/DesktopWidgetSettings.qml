import QtQuick

Item {
  id: root

  property var pluginApi: null
  property var widgetSettings: null

  implicitWidth: 200
  implicitHeight: 100

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
    console.log("FX " + JSON.stringify({ "id": "fx-declares", "entry": "desktopWidgetSettings", "phase": phase, "ctx": ctx }));
  }

  Component.onCompleted: fxLog("completed")
  onWidgetSettingsChanged: fxLog("changed:widgetSettings")
}
