import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NButton {
  property ShellScreen screen
  property real scaling: 1.0

  
  enabled: Settings.data.wallpaper.enabled
  outlined: true
  icon: "wallpaper-selector"
  text: "Wallpaper"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  onClicked: PanelService.getPanel("wallpaperPanel")?.toggle(this)
  onRightClicked: WallpaperService.setRandomWallpaper()
}
