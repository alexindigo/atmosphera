import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  // NIconButton must only define screen, not scaling
  property ShellScreen screen

  baseSize: Style.capsuleHeight
  compact: (Settings.data.bar.density === "compact")
  icon: "wallpaper-selector"
  tooltipText: I18n.tr("tooltips.open-wallpaper-selector")
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: PanelService.getPanel("wallpaperPanel")?.toggle(this)
}
