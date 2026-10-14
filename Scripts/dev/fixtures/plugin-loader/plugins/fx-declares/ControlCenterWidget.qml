import QtQuick

Item {
  id: root

  property var pluginApi: null
  property var screen: null
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property var widgetSettings: null

  readonly property string fxScreen: screen.name

  implicitWidth: 200
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
    console.log("FX " + JSON.stringify({ "id": "fx-declares", "entry": "controlCenterWidget", "phase": phase, "ctx": ctx }));
  }

  Component.onCompleted: fxLog("completed")
  onScreenChanged: fxLog("changed:screen")
  onWidgetIdChanged: fxLog("changed:widgetId")
  onSectionChanged: fxLog("changed:section")
  onSectionWidgetIndexChanged: fxLog("changed:sectionWidgetIndex")
  onSectionWidgetsCountChanged: fxLog("changed:sectionWidgetsCount")
  onWidgetSettingsChanged: fxLog("changed:widgetSettings")
}
