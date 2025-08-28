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
  property real scaling: ScalingService.scale(screen)

  visible: Settings.data.network.bluetoothEnabled
  sizeRatio: 0.8
  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  icon: "bluetooth"
  tooltipText: "Bluetooth Devices"
  onClicked: PanelService.getPanel("bluetoothPanel")?.toggle(screen, this)
}
