import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  baseSize: Style.capsuleHeight
  compact: (Settings.data.bar.density === "compact")
  icon: "wallpaper-selector"
  tooltipText: I18n.tr("tooltips.open-wallpaper-selector")
  tooltipPositionAbove: Settings.data.bar.position === "bottom"
  tooltipPositionLeft: Settings.data.bar.position === "right"
  tooltipPositionRight: Settings.data.bar.position === "left"
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: PanelService.getPanel("wallpaperPanel")?.toggle(this)
}
