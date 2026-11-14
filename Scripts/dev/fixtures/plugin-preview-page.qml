import QtQuick
import qs.Widgets

Column {
  id: root
  required property var pluginApi
  property string labelText: pluginApi.pluginSettings.label
  property bool stageOnSave: true
  readonly property bool settingsDirty: labelText !== pluginApi.initialSettings.label
  function change(value) {
    labelText = value;
    if (!pluginApi.previewSettings({
                                     label: value
                                   }))
      throw new Error("preview refused");
  }
  function saveSettings() {
    if(stageOnSave)pluginApi.pluginSettings.label = labelText;
    pluginApi.saveSettings();
  }
  NTextInput {
    text: root.labelText
    onTextEdited: root.change(text)
  }
}
