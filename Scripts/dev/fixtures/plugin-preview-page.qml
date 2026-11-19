import QtQuick
import qs.Widgets

Column {
  id: root
  required property var pluginApi
  property string labelText: pluginApi.pluginSettings.label
  readonly property bool settingsDirty: labelText !== pluginApi.initialSettings.label
  function change(value) {
    labelText = value;
    if (!pluginApi.previewSettings({
                                     label: value
                                   }))
      throw new Error("preview refused");
  }
  function saveSettings() {
    pluginApi.pluginSettings.label = labelText;
    pluginApi.saveSettings();
  }
  NTextInput {
    text: root.labelText
    onTextEdited: root.change(text)
  }
}
