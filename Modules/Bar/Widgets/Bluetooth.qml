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

  baseSize: Style.capsuleHeight
  applyUiScale: false
  density: Settings.data.bar.density
  colorBg: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  tooltipText: I18n.tr("tooltips.bluetooth-devices")
  tooltipDirection: BarService.getTooltipDirection()
  icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
  onClicked: PanelService.getPanel("bluetoothPanel")?.toggle(this)
  onRightClicked: PanelService.getPanel("bluetoothPanel")?.toggle(this)
}
