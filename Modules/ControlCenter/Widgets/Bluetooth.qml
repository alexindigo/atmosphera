import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

  text: "Bluetooth"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
  active: BluetoothService.enabled
  tooltipText: BluetoothService.enabled ? "Bluetooth enabled" : "Bluetooth disabled"
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  onClicked: PanelService.getPanel("bluetoothPanel")?.toggle(this)
}
