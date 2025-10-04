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
    property bool shouldBeActive: CompositorService.isNiri && Settings.data.wallpaper.enabled && modelData && CompositorService.backend?.overviewActive
    property bool isClosing: false
    property Timer unloadTimer: Timer {
      interval: 300  // Delay before actually unloading
      repeat: false
      onTriggered: {
        if (!shouldBeActive && isClosing) {
          parent.active = false
        }
      }
    }
    property Timer debounceTimer: Timer {
      interval: 50  // Debounce rapid state changes
      repeat: false
      onTriggered: {
        handleStateChange()
      }
    }

    active: shouldBeActive || isClosing

    // Handle state transitions with debouncing
    onShouldBeActiveChanged: {
      debounceTimer.restart()
    }

    function handleStateChange() {
      if (shouldBeActive && !isClosing) {
        // Ensure it's active and not closing
        isClosing = false
        unloadTimer.stop()
      } else if (!shouldBeActive && !isClosing && active) {
        // Start fade out process
        isClosing = true
        unloadTimer.start()
      }
    }

    sourceComponent: PanelWindow {
      id: panelWindow
      property bool isClosing: parent ? parent.isClosing : false

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
        const wallpaperPath = WallpaperService.getWallpaper(modelData.name)
        if (wallpaperPath && wallpaperPath !== wallpaper) {
          wallpaper = wallpaperPath
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

        // Handle fade out when closing - use panelWindow's isClosing property
        property bool loaderIsClosing: panelWindow.isClosing
        
        // Update opacity based on closing state
        onLoaderIsClosingChanged: {
          if (loaderIsClosing) {
            opacity = 0
          } else {
            opacity = 1
          }
        }

        Image {
          id: bgImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          source: wallpaper
          smooth: true
          mipmap: false
          cache: false
          asynchronous: true
          
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
