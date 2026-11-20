import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Compositor
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property bool settingsDirty: false

  readonly property var auxButtons: [
    {
      text: "Preview",
      icon: Icon.eye,
      clicked: function () {
        if (PanelService.lockScreen && !PanelService.lockScreen.active) {
          saveSettings();
          PanelService.lockScreen.showPreview();
        }
      }
    }
  ]

  spacing: Style.marginL

  NPluginSettingsField {
    field: root.pluginApi?.field("showMediaControls") ?? null
    NToggle {
      label: "Show media controls"
      checked: pluginApi?.pluginSettings?.showMediaControls !== false
      onToggled: checked => {
        root.pluginApi.field("showMediaControls").set(checked);
        saveSettings();
      }
    }
  }

  NPluginSettingsField {
    field: root.pluginApi?.field("showSessionButtons") ?? null
    NToggle {
      label: "Show session buttons"
      checked: pluginApi?.pluginSettings?.showSessionButtons !== false
      onToggled: checked => {
        root.pluginApi.field("showSessionButtons").set(checked);
        saveSettings();
      }
    }
  }

  function saveSettings() {
    if (pluginApi)
      pluginApi.saveSettings();
  }
}
