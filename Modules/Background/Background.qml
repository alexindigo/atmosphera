import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Variants {
  id: backgroundVariants
  model: Quickshell.screens

  delegate: Loader {

    required property ShellScreen modelData

    active: Settings.isLoaded && WallpaperService.getWallpaper(modelData.name)

    sourceComponent: PanelWindow {
      id: root

      // Internal state management
      property bool firstWallpaper: true
      property bool transitioning: false
      property real transitionProgress: 0.0

      // Swipe direction: 0=left, 1=right, 2=up, 3=down
      property real swipeDirection: 0
      property real swipeSmoothness: 0.05

      // External state management
      property string servicedWallpaper: WallpaperService.getWallpaper(modelData.name)
      onServicedWallpaperChanged: {
        if (servicedWallpaper && servicedWallpaper !== currentWallpaper.source) {

          // Set wallpaper immediately on startup
          if (firstWallpaper) {
            firstWallpaper = false
            setWallpaperImmediate(servicedWallpaper)
            return
          }

          switch (Settings.data.wallpaper.transitionType) {
            case "none":
              setWallpaperImmediate(servicedWallpaper)
              break
            case "swipe_left":
              swipeDirection = 0
              setWallpaperWithTransition(servicedWallpaper)
              break
            case "swipe_right":
              swipeDirection = 1
              setWallpaperWithTransition(servicedWallpaper)
              break
            case "swipe_up":
              swipeDirection = 2
              setWallpaperWithTransition(servicedWallpaper)
              break
            case "swipe_down":
              swipeDirection = 3
              setWallpaperWithTransition(servicedWallpaper)
              break
            default:
              setWallpaperWithTransition(servicedWallpaper)
              break
          }
        }
      }

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
        id: currentWallpaper
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: ""
        cache: true
        smooth: true
        mipmap: false
        visible: false
      }

      Image {
        id: nextWallpaper
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: ""
        cache: true
        smooth: true
        mipmap: false
        visible: false
      }

      // Fade transition shader
      ShaderEffect {
        id: fadeShader
        anchors.fill: parent
        visible: Settings.data.wallpaper.transitionType === 'fade'

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real fade: transitionProgress
        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_fade.frag.qsb")
      }

      // Swipe transition shader
      ShaderEffect {
        id: swipeShader
        anchors.fill: parent
        visible: Settings.data.wallpaper.transitionType.startsWith('swipe_')

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real progress: transitionProgress
        property real direction: swipeDirection
        property real smoothness: swipeSmoothness
        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_swipe.frag.qsb")
      }

      // Animation for the transition progress
      NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: Settings.data.wallpaper.transitionDuration ?? 1000
        easing.type: {
          const transitionType = Settings.data.wallpaper.transitionType ?? 'fade'
          if (transitionType.startsWith('swipe_')) {
            return Easing.InOutCubic
          }
          return Easing.InOutCubic
        }

        onFinished: {
          // Swap images after transition completes
          currentWallpaper.source = nextWallpaper.source
          transitionProgress = 0.0
          transitioning = false
        }
      }

      function startTransition() {
        if (!transitioning && nextWallpaper.source != currentWallpaper.source) {
          transitioning = true
          transitionAnimation.start()
        }
      }

      function setWallpaperImmediate(source) {
        currentWallpaper.source = source
        nextWallpaper.source = source
        transitionProgress = 0.0
        transitioning = false
      }

      function setWallpaperWithTransition(source) {
        if (source != currentWallpaper.source) {

          if (transitioning) {
            // We are interrupting a transition
            currentWallpaper.source = nextWallpaper.source
            transitionAnimation.stop()
            transitionProgress = 0
            transitioning = false
          }

          nextWallpaper.source = source
          startTransition()
        }
      }
    }
  }
}
