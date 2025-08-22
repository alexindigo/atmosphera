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

  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  icon: {
    // Show different icons based on connection status
    if (BluetoothService.pairedDevices.length > 0) {
      return "bluetooth_connected"
    } else if (BluetoothService.discovering) {
      return "bluetooth_searching"
    } else {
      return "bluetooth"
    }
  }
  tooltipText: "Bluetooth Devices"
  onClicked: {
    bluetoothPanel.toggle(screen)
  }

  Loader {
    id: bluetoothPanel
    source: "BluetoothPanel.qml"
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
