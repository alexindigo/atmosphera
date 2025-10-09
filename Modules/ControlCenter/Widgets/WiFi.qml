import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NButton {
  property ShellScreen screen
  property real scaling: 1.0


  outlined: true
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
      Logger.error("Wi-Fi", "Error getting icon:", error)
      return "signal_wifi_bad"
    }
  }
  text: {
    if (NetworkService.ethernetConnected) {
      return "Network"
    }
    return "Wi-Fi"
  }
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  onClicked: PanelService.getPanel("wifiPanel")?.toggle(this)
}
