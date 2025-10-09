import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

  enabled: ProgramCheckerService.wlsunsetAvailable
  text: "Night Light"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  icon: Settings.data.nightLight.enabled ? (Settings.data.nightLight.forced ? "nightlight-forced" : "nightlight-on") : "nightlight-off"
  active: Settings.data.nightLight.enabled
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"
  tooltipText: {
    if (!Settings.data.nightLight.enabled) {
      return "Turn on Night Light"
    } else if (Settings.data.nightLight.forced) {
      return "Night Light forced on"
    } else {
      return "Turn off Night Light"
    }
  }

  onClicked: {
    if (!Settings.data.nightLight.enabled) {
      Settings.data.nightLight.enabled = true
      Settings.data.nightLight.forced = false
    } else if (Settings.data.nightLight.enabled && !Settings.data.nightLight.forced) {
      Settings.data.nightLight.forced = true
    } else {
      Settings.data.nightLight.enabled = false
      Settings.data.nightLight.forced = false
    }
  }

  onRightClicked: {
    var settingsPanel = PanelService.getPanel("settingsPanel")
    settingsPanel.requestedTab = SettingsPanel.Tab.Display
    settingsPanel.open()
  }
}
