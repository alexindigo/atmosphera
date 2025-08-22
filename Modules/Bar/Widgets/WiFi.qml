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

  sizeMultiplier: 0.8

  Component.onCompleted: {
    Logger.log("WiFi", "Widget component completed")
    Logger.log("WiFi", "NetworkService available:", !!NetworkService)
    if (NetworkService) {
      Logger.log("WiFi", "NetworkService.networks available:", !!NetworkService.networks)
    }
  }

  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  icon: {
    try {
      let connected = false
      let signalStrength = 0
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          connected = true
          signalStrength = NetworkService.networks[net].signal
          break
        }
      }
      return connected ? NetworkService.signalIcon(signalStrength) : "wifi"
    } catch (error) {
      Logger.error("WiFi", "Error getting icon:", error)
      return "wifi"
    }
  }
  tooltipText: "WiFi Networks"
  onClicked: {
    try {
      Logger.log("WiFi", "Button clicked, toggling panel")
      wifiPanel.toggle(screen)
    } catch (error) {
      Logger.error("WiFi", "Error toggling panel:", error)
    }
  }

  Loader {
    id: wifiPanel
    source: "WiFiPanel.qml"
    active: false
    
    property var pendingToggleScreen: null
    
    onStatusChanged: {
      if (status === Loader.Ready && item && pendingToggleScreen !== null) {
        item.toggle(pendingToggleScreen)
        pendingToggleScreen = null
      }
    }
    
    function toggle(screen) {
      // Load the panel if it's not already loaded
      if (!active) {
        active = true
        pendingToggleScreen = screen
      } else if (status === Loader.Ready && item) {
        item.toggle(screen)
      } else {
        pendingToggleScreen = screen
      }
    }
  }
}
