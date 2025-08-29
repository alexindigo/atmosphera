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
      property bool transitioning: false
      property real fadeValue: 0.0
      property bool firstWallpaper: true

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

          if (Settings.data.wallpaper.transitionType === 'fade') {
            setWallpaperWithTransition(servicedWallpaper)
          } else {
            setWallpaperImmediate(servicedWallpaper)
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

      ShaderEffect {
        id: shaderEffect
        anchors.fill: parent

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real fade: fadeValue
        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/mix_images.frag.qsb")
      }

      // Animation for the fade value
      NumberAnimation {
        id: fadeAnimation
        target: root
        property: "fadeValue"
        from: 0.0
        to: 1.0
        duration: Settings.data.wallpaper.transitionDuration
        easing.type: Easing.InOutQuad

        onFinished: {
          // Swap images after transition completes
          currentWallpaper.source = nextWallpaper.source
          fadeValue = 0.0
          transitioning = false
        }
      }

      function startTransition() {
        if (!transitioning && nextWallpaper.source != currentWallpaper.source) {
          transitioning = true
          fadeAnimation.start()
        }
      }

      function setWallpaperImmediate(source) {
        currentWallpaper.source = source
        nextWallpaper.source = source
        fadeValue = 0.0
        transitioning = false
      }

      function setWallpaperWithTransition(source) {
        if (source != currentWallpaper.source) {

          if (transitioning) {
            // we are interupting a transition
            if (fadeValue >= 0.5) {

            }
            currentWallpaper.source = nextWallpaper.source
            fadeAnimation.stop()
            fadeValue = 0
            transitioning = false
          }

          nextWallpaper.source = source
          startTransition()
        }
      }
    }
  }
}
