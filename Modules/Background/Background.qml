import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

Variants {
  id: backgroundVariants
  model: Quickshell.screens

  delegate: Loader {

    required property ShellScreen modelData

    active: modelData && Settings.data.wallpaper.enabled && (!PowerProfileService.atmospheraPerformanceMode || !Settings.data.atmospheraPerformance.disableWallpaper)

    sourceComponent: PanelWindow {
      id: root

      // Internal state management
      property string transitionType: "fade"
      property real transitionProgress: 0
      property bool isStartupTransition: true
      property bool wallpaperReady: false
      property string errorReason: ""
      property int _front: 0
      property int _pending: -1
      property int _generation: 0
      property int _candidateGeneration: -1
      property bool _animateCandidate: false
      property string _displayedPath: ""
      property var _acknowledgment: null
      property var _presentationConnection: null
      readonly property var _presentationWindow: shaderLoader.Window.window
      readonly property var currentWallpaper: _front === 0 ? firstWallpaper : secondWallpaper
      readonly property var nextWallpaper: _front === 0 ? secondWallpaper : firstWallpaper

      // ImvImage decodes only in a visible scene. The transparent layer owns
      // the pending texture; nothing is drawn until the shader has a frame.
      visible: true

      readonly property real edgeSmoothness: Settings.data.wallpaper.transitionEdgeSmoothness
      readonly property var allTransitions: WallpaperService.allTransitions
      readonly property bool transitioning: transitionAnimation.running

      // Wipe direction: 0=left, 1=right, 2=up, 3=down
      property real wipeDirection: 0

      // Disc
      property real discCenterX: 0.5
      property real discCenterY: 0.5

      // Stripe
      property real stripesCount: 16
      property real stripesAngle: 0

      // Pixelate
      property real pixelateMaxBlockSize: 64.0

      // Honeycomb
      property real honeycombCellSize: 0.04
      property real honeycombCenterX: 0.5
      property real honeycombCenterY: 0.5

      // Used to debounce wallpaper changes
      property string futureWallpaper: ""
      // Track the original wallpaper path being transitioned to (before caching)
      property string transitioningToOriginalPath: ""

      // Fillmode default is "crop"
      property real fillMode: WallpaperService.getFillModeUniform()
      property color _fillColor: Settings.data.wallpaper.fillColor
      property vector4d fillColor: Qt.vector4d(_fillColor.r, _fillColor.g, _fillColor.b, 1.0)

      // Solid color mode - track whether current/next are solid colors
      property bool isSolid1: false
      property bool isSolid2: false
      property color _solidColor1: Settings.data.wallpaper.solidColor
      property color _solidColor2: Settings.data.wallpaper.solidColor
      property vector4d solidColor1: Qt.vector4d(_solidColor1.r, _solidColor1.g, _solidColor1.b, 1.0)
      property vector4d solidColor2: Qt.vector4d(_solidColor2.r, _solidColor2.g, _solidColor2.b, 1.0)

      Component.onCompleted: setWallpaperInitial()
      on_PresentationWindowChanged: _bindPresentation()

      Component.onDestruction: {
        _clearAcknowledgment();
        transitionAnimation.stop();
        startupTransitionTimer.stop();
        debounceTimer.stop();
        shaderLoader.active = false;
        ++_generation;
        firstWallpaper.active = secondWallpaper.active = false;
        firstWallpaper.source = secondWallpaper.source = "";
      }

      function _unbindPresentation() {
        const fence = _presentationConnection;
        _presentationConnection = null;
        if (fence?.window) {
          fence.window.afterSynchronizing.disconnect(fence.sync);
          fence.window.frameSwapped.disconnect(fence.swap);
        }
      }

      function _clearAcknowledgment() {
        _acknowledgment = null;
        _unbindPresentation();
      }

      function _bindPresentation() {
        _unbindPresentation();
        const acknowledgment = _acknowledgment;
        const window = _presentationWindow;
        if (!acknowledgment || !window)
          return;
        let synchronized = false;
        const fence = {
          window: window,
          sync: () => {
            synchronized = true;
          },
          swap: () => {
            if (!synchronized || root._presentationConnection !== fence || acknowledgment.generation !== root._generation)
              return;
            root._clearAcknowledgment();
            WallpaperService.wallpaperProcessingComplete(modelData.name, acknowledgment.path, acknowledgment.output);
          }
        };
        _presentationConnection = fence;
        // Subscribe after promotion, so any sync we observe includes the
        // promoted wallpaper. An older in-flight swap can arrive first, but
        // its render thread posts it before the new frame's sync notification.
        window.afterSynchronizing.connect(fence.sync);
        window.frameSwapped.connect(fence.swap);
        window.update();
      }

      Connections {
        target: Settings.data.wallpaper
        function onFillModeChanged() {
          fillMode = WallpaperService.getFillModeUniform();
        }
      }

      // External state management
      Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
          if (screenName === modelData.name) {
            requestPreprocessedWallpaper(path);
          }
        }
      }

      Connections {
        target: CompositorService
        function onDisplayScalesChanged() {
          if (!WallpaperService.isInitialized) {
            return;
          }

          const currentPath = WallpaperService.getWallpaper(modelData.name);
          if (!currentPath || WallpaperService.isSolidColorPath(currentPath)) {
            return;
          }

          requestPreprocessedWallpaper(currentPath);
        }
      }

      color: "transparent"
      screen: modelData
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "atmosphera-wallpaper-" + (screen?.name || "unknown")

      anchors {
        bottom: true
        top: true
        right: true
        left: true
      }

      Timer {
        id: debounceTimer
        interval: 333
        running: false
        repeat: false
        onTriggered: changeWallpaper()
      }

      // Delay startup transition to ensure the compositor has mapped the window
      Timer {
        id: startupTransitionTimer
        interval: 100
        running: false
        repeat: false
        onTriggered: _executeStartupTransition()
      }

      NImage {
        id: firstWallpaper
        anchors.fill: parent
        active: false
        source: ""
        animationIntent: "still"
        imageTransform: "contain"
        fillMode: Image.Stretch // The wallpaper shader owns fit/crop exactly once.
        smooth: true
        mipmap: false
        textureOnly: true
        onStatusChanged: Qt.callLater(root._settleCandidate, 0)
      }

      NImage {
        id: secondWallpaper
        anchors.fill: parent
        active: false
        source: ""
        animationIntent: "still"
        imageTransform: "contain"
        fillMode: Image.Stretch
        smooth: true
        mipmap: false
        textureOnly: true
        onStatusChanged: Qt.callLater(root._settleCandidate, 1)
      }

      // Dynamic shader loader - only loads the active transition shader
      Loader {
        id: shaderLoader
        anchors.fill: parent
        active: true
        visible: root.wallpaperReady

        sourceComponent: {
          switch (transitionType) {
          case "wipe":
            return wipeShaderComponent;
          case "disc":
            return discShaderComponent;
          case "stripes":
            return stripesShaderComponent;
          case "pixelate":
            return pixelateShaderComponent;
          case "honeycomb":
            return honeycombShaderComponent;
          case "fade":
          case "none":
          default:
            return fadeShaderComponent;
          }
        }
      }

      // Fade or None transition shader component
      Component {
        id: fadeShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: root.currentWallpaper.textureItem
          property variant source2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.textureItem : root.currentWallpaper.textureItem
          property real progress: root.transitionProgress

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.currentWallpaper.decodedSize.width
          property real imageHeight1: root.currentWallpaper.decodedSize.height
          property real imageWidth2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.width : imageWidth1
          property real imageHeight2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.height : imageHeight1
          property real screenWidth: width
          property real screenHeight: height

          // Solid color mode
          property real isSolid1: root.isSolid1 ? 1.0 : 0.0
          property real isSolid2: root.isSolid2 ? 1.0 : 0.0
          property vector4d solidColor1: root.solidColor1
          property vector4d solidColor2: root.solidColor2

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_fade.frag.qsb")
        }
      }

      // Wipe transition shader component
      Component {
        id: wipeShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: root.currentWallpaper.textureItem
          property variant source2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.textureItem : root.currentWallpaper.textureItem
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real direction: root.wipeDirection

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.currentWallpaper.decodedSize.width
          property real imageHeight1: root.currentWallpaper.decodedSize.height
          property real imageWidth2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.width : imageWidth1
          property real imageHeight2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.height : imageHeight1
          property real screenWidth: width
          property real screenHeight: height

          // Solid color mode
          property real isSolid1: root.isSolid1 ? 1.0 : 0.0
          property real isSolid2: root.isSolid2 ? 1.0 : 0.0
          property vector4d solidColor1: root.solidColor1
          property vector4d solidColor2: root.solidColor2

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_wipe.frag.qsb")
        }
      }

      // Disc reveal transition shader component
      Component {
        id: discShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: root.currentWallpaper.textureItem
          property variant source2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.textureItem : root.currentWallpaper.textureItem
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real aspectRatio: root.width / root.height
          property real centerX: root.discCenterX
          property real centerY: root.discCenterY

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.currentWallpaper.decodedSize.width
          property real imageHeight1: root.currentWallpaper.decodedSize.height
          property real imageWidth2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.width : imageWidth1
          property real imageHeight2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.height : imageHeight1
          property real screenWidth: width
          property real screenHeight: height

          // Solid color mode
          property real isSolid1: root.isSolid1 ? 1.0 : 0.0
          property real isSolid2: root.isSolid2 ? 1.0 : 0.0
          property vector4d solidColor1: root.solidColor1
          property vector4d solidColor2: root.solidColor2

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_disc.frag.qsb")
        }
      }

      // Diagonal stripes transition shader component
      Component {
        id: stripesShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: root.currentWallpaper.textureItem
          property variant source2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.textureItem : root.currentWallpaper.textureItem
          property real progress: root.transitionProgress
          property real smoothness: root.edgeSmoothness
          property real aspectRatio: root.width / root.height
          property real stripeCount: root.stripesCount
          property real angle: root.stripesAngle

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.currentWallpaper.decodedSize.width
          property real imageHeight1: root.currentWallpaper.decodedSize.height
          property real imageWidth2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.width : imageWidth1
          property real imageHeight2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.height : imageHeight1
          property real screenWidth: width
          property real screenHeight: height

          // Solid color mode
          property real isSolid1: root.isSolid1 ? 1.0 : 0.0
          property real isSolid2: root.isSolid2 ? 1.0 : 0.0
          property vector4d solidColor1: root.solidColor1
          property vector4d solidColor2: root.solidColor2

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_stripes.frag.qsb")
        }
      }

      // Pixelate transition shader component
      Component {
        id: pixelateShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: root.currentWallpaper.textureItem
          property variant source2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.textureItem : root.currentWallpaper.textureItem
          property real progress: root.transitionProgress
          property real maxBlockSize: root.pixelateMaxBlockSize

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.currentWallpaper.decodedSize.width
          property real imageHeight1: root.currentWallpaper.decodedSize.height
          property real imageWidth2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.width : imageWidth1
          property real imageHeight2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.height : imageHeight1
          property real screenWidth: width
          property real screenHeight: height

          // Solid color mode
          property real isSolid1: root.isSolid1 ? 1.0 : 0.0
          property real isSolid2: root.isSolid2 ? 1.0 : 0.0
          property vector4d solidColor1: root.solidColor1
          property vector4d solidColor2: root.solidColor2

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_pixelate.frag.qsb")
        }
      }

      // Honeycomb transition shader component
      Component {
        id: honeycombShaderComponent
        ShaderEffect {
          anchors.fill: parent

          property variant source1: root.currentWallpaper.textureItem
          property variant source2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.textureItem : root.currentWallpaper.textureItem
          property real progress: root.transitionProgress
          property real cellSize: root.honeycombCellSize
          property real centerX: root.honeycombCenterX
          property real centerY: root.honeycombCenterY
          property real aspectRatio: root.width / root.height

          // Fill mode properties
          property real fillMode: root.fillMode
          property vector4d fillColor: root.fillColor
          property real imageWidth1: root.currentWallpaper.decodedSize.width
          property real imageHeight1: root.currentWallpaper.decodedSize.height
          property real imageWidth2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.width : imageWidth1
          property real imageHeight2: root.nextWallpaper.status === Image.Ready ? root.nextWallpaper.decodedSize.height : imageHeight1
          property real screenWidth: width
          property real screenHeight: height

          // Solid color mode
          property real isSolid1: root.isSolid1 ? 1.0 : 0.0
          property real isSolid2: root.isSolid2 ? 1.0 : 0.0
          property vector4d solidColor1: root.solidColor1
          property vector4d solidColor2: root.solidColor2

          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/wp_honeycomb.frag.qsb")
        }
      }

      // Animation for the transition progress
      NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: Settings.data.wallpaper.transitionDuration
        easing.type: Easing.InOutCubic
        onFinished: root._promote(true)
      }

      // ------------------------------------------------------
      function setWallpaperInitial() {
        // On startup, defer assigning wallpaper until the services are ready
        if (!WallpaperService || !WallpaperService.isInitialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }
        if (!ImageCacheService || !ImageCacheService.initialized) {
          Qt.callLater(setWallpaperInitial);
          return;
        }

        requestPreprocessedWallpaper(Settings.data.wallpaper.useSolidColor ? WallpaperService.createSolidColorPath(Settings.data.wallpaper.solidColor.toString()) : WallpaperService.getWallpaper(modelData.name));
      }

      // ------------------------------------------------------
      function requestPreprocessedWallpaper(originalPath) {
        if (!originalPath)
          return;
        ++_generation;
        _clearAcknowledgment();
        startupTransitionTimer.stop();
        debounceTimer.stop();
        if (transitioning) {
          transitionAnimation.stop();
          _promote(false);
        }
        _pending = -1;
        nextWallpaper.active = false;
        nextWallpaper.source = "";
        isSolid2 = false;
        errorReason = "";
        futureWallpaper = String(originalPath);
        transitioningToOriginalPath = futureWallpaper;
        if (isStartupTransition)
          performStartupTransition();
        else
          debounceTimer.restart();
      }

      // ------------------------------------------------------
      function setWallpaperImmediate(source) {
        _startTransitionTo(source, WallpaperService.isSolidColorPath(source), false);
      }

      // ------------------------------------------------------
      function setWallpaperWithTransition(source) {
        _startTransitionTo(source, WallpaperService.isSolidColorPath(source), true);
      }

      // Helper to start transition to a new source
      function _startTransitionTo(source, isSolidSource, animate) {
        _pending = 1 - _front;
        _candidateGeneration = _generation;
        _animateCandidate = animate;
        isSolid2 = isSolidSource;
        nextWallpaper.active = false;
        nextWallpaper.source = "";
        if (isSolidSource) {
          _solidColor2 = WallpaperService.getSolidColor(source);
          _candidateReady();
        } else {
          var scale = CompositorService.getDisplayScale(modelData.name);
          // Capture the preference on the candidate, not the displayed slot.
          // A preference change must not invalidate the front texture.
          nextWallpaper.normalize = !Settings.data.wallpaper.useOriginalImages;
          nextWallpaper.sourceSize = Qt.size(Math.max(1, Math.round(modelData.width * scale)), Math.max(1, Math.round(modelData.height * scale)));
          nextWallpaper.source = source;
          nextWallpaper.active = true;
        }
      }

      function _settleCandidate(index) {
        if (_pending !== index || _candidateGeneration !== _generation || isSolid2 || transitioning)
          return;
        if (nextWallpaper.status === Image.Ready) {
          _candidateReady();
        } else if (nextWallpaper.status === Image.Error) {
          errorReason = nextWallpaper.errorReason;
          Logger.w("Background", "Wallpaper unavailable:", errorReason);
          _pending = -1;
          transitioningToOriginalPath = "";
          nextWallpaper.active = false;
          nextWallpaper.source = "";
        }
      }

      function _candidateReady() {
        wallpaperReady = true;
        if (_animateCandidate)
          transitionAnimation.start();
        else
          _promote(true);
      }

      function _promote(acknowledge) {
        if (_pending < 0)
          return;
        var generation = _generation;
        var path = transitioningToOriginalPath;
        isSolid1 = isSolid2;
        _solidColor1 = _solidColor2;
        _front = _pending;
        _pending = -1;
        _displayedPath = path;
        transitionProgress = 0;
        nextWallpaper.active = false;
        nextWallpaper.source = "";
        isSolid2 = false;
        isStartupTransition = false;
        transitioningToOriginalPath = "";
        var output = isSolid1 ? "" : currentWallpaper.outputUrl;
        if (acknowledge) {
          _acknowledgment = {
            generation: generation,
            path: path,
            output: output
          };
          _bindPresentation();
        }
      }

      // ------------------------------------------------------
      // Main method that actually trigger the wallpaper change
      function changeWallpaper() {
        // Pick a transition from the user's selected list
        var selected = Settings.data.wallpaper.transitionType;
        if ((isStartupTransition && Settings.data.wallpaper.skipStartupTransition) || !selected || selected.length === 0) {
          transitionType = "none";
        } else if (selected.length === 1) {
          transitionType = selected[0];
        } else {
          var index = Math.floor(Math.random() * selected.length);
          transitionType = selected[index];
        }

        // Ensure the transition type really exists
        if (transitionType !== "none" && !allTransitions.includes(transitionType)) {
          transitionType = "fade";
        }

        //Logger.i("Background", "New wallpaper: ", futureWallpaper, "On:", modelData.name, "Transition:", transitionType)
        switch (transitionType) {
        case "none":
          setWallpaperImmediate(futureWallpaper);
          break;
        case "wipe":
          wipeDirection = Math.random() * 4;
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "disc":
          discCenterX = isStartupTransition ? 0.5 : Math.random();
          discCenterY = isStartupTransition ? 0.5 : Math.random();
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "stripes":
          stripesCount = Math.round(Math.random() * 20 + 4);
          stripesAngle = Math.random() * 360;
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "pixelate":
          pixelateMaxBlockSize = isStartupTransition ? 64.0 : Math.round(Math.random() * 80 + 32);
          setWallpaperWithTransition(futureWallpaper);
          break;
        case "honeycomb":
          honeycombCellSize = isStartupTransition ? 0.04 : Math.random() * 0.04 + 0.02;
          honeycombCenterX = isStartupTransition ? 0.5 : Math.random();
          honeycombCenterY = isStartupTransition ? 0.5 : Math.random();
          setWallpaperWithTransition(futureWallpaper);
          break;
        default:
          setWallpaperWithTransition(futureWallpaper);
          break;
        }
      }

      // ------------------------------------------------------
      // Dedicated function for startup animation
      // Sets up transition params, then defers the actual animation
      // to allow the compositor time to map the window.
      function performStartupTransition() {
        startupTransitionTimer.restart();
      }

      // Actually kick off the startup transition after the delay
      function _executeStartupTransition() {
        changeWallpaper();
      }
    }
  }
}
