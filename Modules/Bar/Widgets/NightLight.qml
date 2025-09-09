import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.SettingsPanel
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  sizeRatio: 0.8
  colorBg: Settings.data.nightLight.enabled ? Color.mPrimary : Color.mSurfaceVariant
  colorFg: Settings.data.nightLight.enabled ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  icon: Bootstrap.icons["moon-stars"]
  tooltipText: `Night light: ${Settings.data.nightLight.enabled ? "enabled." : "disabled."}\nLeft click to toggle.\nRight click to access settings.`
  onClicked: Settings.data.nightLight.enabled = !Settings.data.nightLight.enabled

  onRightClicked: {
    var settingsPanel = PanelService.getPanel("settingsPanel")
    settingsPanel.requestedTab = SettingsPanel.Tab.Brightness
    settingsPanel.open(screen)
  }
}
