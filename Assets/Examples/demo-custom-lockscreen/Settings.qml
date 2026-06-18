import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property string editGreeting: pluginApi?.pluginSettings?.greeting ?? pluginApi?.manifest?.metadata?.defaultSettings?.greeting ?? "Custom Lock Screen"

  // Auxiliary buttons shown on the left side of the settings popup's button row
  readonly property var auxButtons: [
    {
      text: "Preview",
      icon: "eye",
      clicked: function () {
        if (PanelService.lockScreen && !PanelService.lockScreen.active) {
          pluginApi.pluginSettings.greeting = root.editGreeting;
          pluginApi.saveSettings();
          PanelService.lockScreen.active = true;
          PanelService.lockScreen.previewMode = true;
        }
      }
    }
  ]

  spacing: Style.marginM

  NTextInput {
    Layout.fillWidth: true
    label: "Greeting text"
    placeholderText: "Hello!"
    text: root.editGreeting
    onTextChanged: root.editGreeting = text
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings.greeting = root.editGreeting;
    pluginApi.saveSettings();
  }
}
