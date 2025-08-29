import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Variants {
  model: Quickshell.screens

  delegate: Loader {

    required property ShellScreen modelData

    active: Settings.isLoaded && WallpaperService.getWallpaper(modelData.name)

    sourceComponent: PanelWindow {

      color: Color.transparent
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "quickshell-wallpaper"

      anchors {
        bottom: true
        top: true
        right: true
        left: true
      }

      Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: WallpaperService.getWallpaper(modelData.name)
        cache: true
        smooth: true
        mipmap: false
      }
    }
  }
}
