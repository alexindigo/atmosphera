import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  tooltipText: I18n.tr("tooltips.manage-wifi")
  tooltipDirection: BarService.getTooltipDirection()
  icon: {
    try {
      if (NetworkService.ethernetConnected) {
        return "ethernet"
      }
      let connected = false
      let signalStrength = 0
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          connected = true
          signalStrength = NetworkService.networks[net].signal
          break
        }
      }
      return connected ? NetworkService.signalIcon(signalStrength) : "wifi-off"
    } catch (error) {
      Logger.e("Wi-Fi", "Error getting icon:", error)
      return "signal_wifi_bad"
    }
  }
  onClicked: PanelService.getPanel("wifiPanel")?.toggle(this)
  onRightClicked: PanelService.getPanel("wifiPanel")?.toggle(this)
}
