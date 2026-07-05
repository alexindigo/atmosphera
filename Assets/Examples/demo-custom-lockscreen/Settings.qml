import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Media
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  readonly property var auxButtons: [
    {
      text: "Preview",
      icon: Icon.eye,
      clicked: function () {
        if (PanelService.lockScreen && !PanelService.lockScreen.active) {
          saveSettings();
          PanelService.lockScreen.active = true;
          PanelService.lockScreen.previewMode = true;
        }
      }
    }
  ]

  spacing: Style.marginL

  NToggle {
    label: "Show media controls"
    checked: pluginApi?.pluginSettings?.showMediaControls !== false
    onToggled: checked => {
      pluginApi.pluginSettings.showMediaControls = checked;
      saveSettings();
    }
  }

  NToggle {
    label: "Show session buttons"
    checked: pluginApi?.pluginSettings?.showSessionButtons !== false
    onToggled: checked => {
      pluginApi.pluginSettings.showSessionButtons = checked;
      saveSettings();
    }
  }

  function saveSettings() {
    if (pluginApi)
      pluginApi.saveSettings();
  }
}
