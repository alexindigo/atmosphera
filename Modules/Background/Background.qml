import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  active: true

  sourceComponent: Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      required property ShellScreen modelData
      property string wallpaperSource: WallpaperService.getWallpaper(modelData.name)

      visible: wallpaperSource !== ""
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

      margins {
        top: 0
      }

      Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: wallpaperSource
        visible: wallpaperSource !== ""
        cache: true
        smooth: true
        mipmap: false
      }
    }
  }
}
