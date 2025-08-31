import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Variants {
  model: Quickshell.screens

  delegate: Loader {
    required property ShellScreen modelData

    active: Settings.isLoaded && CompositorService.isNiri && modelData

    sourceComponent: PanelWindow {
      Component.onCompleted: {
        if (modelData) {
          Logger.log("Overview", "Loading Overview component for Niri on", modelData.name)
        }
      }

      color: Color.transparent
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "quickshell-overview"

      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }

      Image {
        id: bgImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: modelData ? WallpaperService.getWallpaper(modelData.name) : ""
        smooth: true
        mipmap: false
        cache: false
      }

      MultiEffect {
        anchors.fill: parent
        source: bgImage
        blurEnabled: true
        blur: 0.48
        blurMax: 128
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.5)
      }
    }
  }
}
