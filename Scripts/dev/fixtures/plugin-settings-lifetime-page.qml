import QtQuick

Item {
  id: root
  property var pluginApi: null
  property string labelText: pluginApi?.field("label")?.value ?? ""
  readonly property bool settingsDirty: labelText !== (pluginApi?.initialSettings.label ?? "")
  property int completions: 0
  property string lastStatus: ""
  function change(value) {
    labelText = value;
    return pluginApi.previewSettings({
                                       label: value
                                     });
  }
  function saveSettings() {
    pluginApi.field("label").set(labelText);
    pluginApi.saveSettings(function (result) {
      root.completions++;
      root.lastStatus = result.status;
    });
  }
}
