import QtQuick
import QtQuick.Controls

// Minimal settings page for the fx-instance fixture. The page edits `labelText`;
// saveSettings() writes it to the plugin api (the instance api when opened from
// a placement, the plugin api otherwise) and saves.
Item {
  id: root

  property var pluginApi: null
  property string labelText: pluginApi ? String(pluginApi.pluginSettings.label) : ""

  implicitWidth: 400
  implicitHeight: 80

  function saveSettings() {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings.label = root.labelText;
    pluginApi.saveSettings();
  }

  TextField {
    id: labelField

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.labelText
    onTextEdited: root.labelText = text
  }
}
