import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

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
  fontWeight: Style.fontWeightMedium
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  active: {
    if (NetworkService.ethernetConnected) {
      return true
    }
    try {
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          return true
        }
      }
      return false
    } catch (error) {
      return false
    }
  }

  tooltipText: {
    if (NetworkService.ethernetConnected) {
      return "Ethernet connected"
    }
    let connected = false
    for (const net in NetworkService.networks) {
      if (NetworkService.networks[net].connected) {
        connected = true
        break
      }
    }
    return connected ? "Wi-Fi connected" : "Wi-Fi disconnected"
  }

  onClicked: PanelService.getPanel("wifiPanel")?.toggle(this)
}
