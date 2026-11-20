import QtQuick
import qs.Widgets

Column {
  id: root
  property var pluginApi: null
  property string labelText: pluginApi ? pluginApi.initialSettings.label : ""
  readonly property bool settingsDirty: pluginApi && labelText !== pluginApi.initialSettings.label
  property int callbacks: 0
  property string lastStatus: ""
  property string completionOrder: ""
  property bool submitInput: true
  function setLabel(value) {
    labelText = value;
  }
  function saveSettings() {
    if (submitInput)
      pluginApi.field("label").set(labelText);
    completionOrder = "";
    pluginApi.saveSettings(function (result) {
      root.callbacks++;
      root.lastStatus = result.status;
      root.completionOrder += ",callback";
    });
    pluginApi.saveSettings(function (result) {
      root.callbacks++;
      root.lastStatus = result.status;
      root.completionOrder += ",callback";
    });
  }
  NText {
    text: root.labelText
  }
  Connections {
    target: root.pluginApi
    function onSettingsCompleted(result) {
      root.completionOrder += "signal";
    }
  }
}
