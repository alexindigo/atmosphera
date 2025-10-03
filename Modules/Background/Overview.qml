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
    property string wallpaper: ""

    active: CompositorService.isNiri && Settings.data.wallpaper.enabled && modelData && CompositorService.backend?.overviewActive

    sourceComponent: PanelWindow {
      id: panelWindow

      Component.onCompleted: {
        if (modelData) {
          Logger.log("Overview", "Loading Overview component for Niri on", modelData.name)
        }
        setWallpaperInitial()
      }

      // External state management
      Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
          if (screenName === modelData.name) {
            wallpaper = path
          }
        }
      }

      function setWallpaperInitial() {
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial)
          return
        }
        wallpaper = WallpaperService.getWallpaper(modelData.name)
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

      // Wrap everything in an Item with opacity animation
      Item {
        id: contentContainer
        anchors.fill: parent
        opacity: 0

        Behavior on opacity {
          NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
          }
        }

        Component.onCompleted: {
          opacity = 1
        }

        Image {
          id: bgImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          source: wallpaper
          smooth: true
          mipmap: false
          cache: false
        }

        MultiEffect {
          anchors.fill: parent
          source: bgImage
          autoPaddingEnabled: false
          blurEnabled: true
          blur: 0.48
          blurMax: 128
        }

        Rectangle {
          anchors.fill: parent
          color: Settings.data.colorSchemes.darkMode ? Qt.alpha(Color.mSurface, Style.opacityMedium) : Qt.alpha(Color.mOnSurface, Style.opacityMedium)
        }
      }
    }
  }
}
