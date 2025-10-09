import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

  enabled: Settings.data.wallpaper.enabled
  icon: "wallpaper-selector"
  text: "Wallpaper"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  active: Settings.data.wallpaper.enabled
  tooltipText: "Open wallpaper selector"
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  onClicked: PanelService.getPanel("wallpaperPanel")?.toggle(this)
  onRightClicked: WallpaperService.setRandomWallpaper()
}
