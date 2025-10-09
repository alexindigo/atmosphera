import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NButton {
  property ShellScreen screen
  property real scaling: 1.0

  outlined: true
  text: "Bluetooth"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
  onClicked: PanelService.getPanel("bluetoothPanel")?.toggle(this)
}
