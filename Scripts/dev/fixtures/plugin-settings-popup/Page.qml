import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  required property var pluginApi
  property string labelText: pluginApi.pluginSettings.label || ""
  readonly property bool settingsDirty: labelText !== pluginApi.pluginSettings.label
  property int saves: 0
  property bool stageOnSave: true
  property int completions: 0
  property string lastStatus: ""

  NTextInput {
    id: labelInput
    Layout.fillWidth: true
    label: "Popup receipt witness"
    text: root.labelText
    onTextChanged: root.labelText = text
  }
  function setLabel(value) {
    labelText = value;
  }
  function editLabel(value) {
    labelInput.inputItem.forceActiveFocus();
    labelInput.inputItem.text = value;
    labelInput.inputItem.textEdited();
  }
  function saveSettings() {
    saves++;
    if (stageOnSave)
      pluginApi.field("label").set(labelText);
    pluginApi.saveSettings(function (result) {
      root.completions++;
      root.lastStatus = result.status;
    });
    // Multiple staging requests still mean a single popup-owned Apply.
    pluginApi.saveSettings(function (result) {
      root.completions++;
    });
  }
}
