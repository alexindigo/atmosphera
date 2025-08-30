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
      property string transitionType: 'fade'
      property bool transitioning: false
      property real transitionProgress: 0
      property real edgeSmoothness: Settings.data.wallpaper.transitionEdgeSmoothness
      readonly property var allTransitions: WallpaperService.allTransitions

      // Wipe direction: 0=left, 1=right, 2=up, 3=down
      property real wipeDirection: 0

      // Disc
      property real discCenterX: 0.5
      property real discCenterY: 0.5

      // Stripe
      property real stripesCount: 16
      property real stripesAngle: 0

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

          // Get the transitionType from the settings
          transitionType = Settings.data.wallpaper.transitionType

          if (transitionType == 'random') {
            var index = Math.floor(Math.random() * allTransitions.length)
            transitionType = allTransitions[index]
          }

          // Ensure the transition type really exists
          if (transitionType !== "none" && !allTransitions.includes(transitionType)) {
            transitionType = 'fade'
          }

          Logger.log("Background", "New wallpaper: ", servicedWallpaper, "On:", modelData.name, "Transition:", transitionType)

          switch (transitionType) {
          case "none":
            setWallpaperImmediate(servicedWallpaper)
            break
          case "wipe_left":
            wipeDirection = 0
            setWallpaperWithTransition(servicedWallpaper)
            break
          case "wipe_right":
            wipeDirection = 1
            setWallpaperWithTransition(servicedWallpaper)
            break
          case "wipe_up":
            wipeDirection = 2
            setWallpaperWithTransition(servicedWallpaper)
            break
          case "wipe_down":
            wipeDirection = 3
            setWallpaperWithTransition(servicedWallpaper)
            break
          case "disc":
            discCenterX = Math.random()
            discCenterY = Math.random()
            setWallpaperWithTransition(servicedWallpaper)
            break
          case "stripes":
            stripesCount = Math.round(Math.random() * 24 + 2)
            stripesAngle = Math.random() * 360
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
        smooth: true
        mipmap: false
        visible: false
        cache: false
      }

      Image {
        id: nextWallpaper
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: ""
        smooth: true
        mipmap: false
        visible: false
        cache: false
      }

      // Fade or None transition shader
      ShaderEffect {
        id: fadeShader
        anchors.fill: parent
        visible: transitionType === 'fade' || transitionType === 'none'

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real progress: root.transitionProgress
        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_fade.frag.qsb")
      }

      // Wipe transition shader
      ShaderEffect {
        id: wipeShader
        anchors.fill: parent
        visible: transitionType.startsWith('wipe_')

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real progress: root.transitionProgress
        property real smoothness: root.edgeSmoothness
        property real direction: root.wipeDirection

        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_wipe.frag.qsb")
      }

      // Disc reveal transition shader
      ShaderEffect {
        id: discShader
        anchors.fill: parent
        visible: transitionType === 'disc'

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real progress: root.transitionProgress
        property real smoothness: root.edgeSmoothness
        property real aspectRatio: root.width / root.height
        property real centerX: root.discCenterX
        property real centerY: root.discCenterY

        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_disc.frag.qsb")
      }

      // Diagonal stripes transition shader
      ShaderEffect {
        id: stripesShader
        anchors.fill: parent
        visible: transitionType === 'stripes'

        property variant source1: currentWallpaper
        property variant source2: nextWallpaper
        property real progress: root.transitionProgress
        property real smoothness: root.edgeSmoothness
        property real aspectRatio: root.width / root.height
        property real stripeCount: root.stripesCount
        property real angle: root.stripesAngle

        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_stripes.frag.qsb")
      }

      // Animation for the transition progress
      NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: Settings.data.wallpaper.transitionDuration ?? 1000
        easing.type: Easing.InOutCubic  //transitionType.startsWith('wipe_') ? Easing.InOutCubic : Easing.OutQuad
        onFinished: {
          // Swap images after transition completes
          currentWallpaper.source = nextWallpaper.source
          nextWallpaper.source = ""
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
        nextWallpaper.source = ""
        transitionProgress = 0.0
        transitioning = false
      }

      function setWallpaperWithTransition(source) {
        if (source != currentWallpaper.source) {

          if (transitioning) {
            // We are interrupting a transition
            transitionAnimation.stop()
            currentWallpaper.source = nextWallpaper.source
            nextWallpaper.source = ""
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
