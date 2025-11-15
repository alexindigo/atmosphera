import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Widgets
import qs.Services.Hardware
import qs.Services.Media
import qs.Services.System

// Unified OSD component that displays volume, input volume, and brightness changes
Variants {
  model: Quickshell.screens.filter(screen => (Settings.data.osd.monitors.includes(screen.name) || Settings.data.osd.monitors.length === 0) && Settings.data.osd.enabled)

  delegate: Loader {
    id: root

    required property ShellScreen modelData

    active: false

    // OSD State
    property string currentOSDType: "" // "volume", "inputVolume", "brightness", or ""

    // Audio Output State
    property real lastKnownVolume: -1
    property bool volumeInitialized: false
    property bool muteInitialized: false

    // Audio Input State
    property real lastKnownInputVolume: -1
    property bool inputInitialized: false

    // Brightness State
    property real lastUpdatedBrightness: 0
    property bool brightnessInitialized: false

    // Current values (computed properties)
    readonly property real currentVolume: AudioService.volume
    readonly property bool isMuted: AudioService.muted
    readonly property real currentInputVolume: AudioService.inputVolume
    readonly property bool isInputMuted: AudioService.inputMuted
    readonly property real currentBrightness: lastUpdatedBrightness

    // ============================================================================
    // Helper Functions
    // ============================================================================
    function getIcon() {
      switch (currentOSDType) {
      case "volume":
        if (isMuted)
          return "volume-mute"
        if (currentVolume <= Number.EPSILON)
          return "volume-zero"
        return currentVolume <= 0.5 ? "volume-low" : "volume-high"
      case "inputVolume":
        return isInputMuted ? "microphone-off" : "microphone"
      case "brightness":
        return currentBrightness <= 0.5 ? "brightness-low" : "brightness-high"
      default:
        return ""
      }
    }

    function getCurrentValue() {
      switch (currentOSDType) {
      case "volume":
        return isMuted ? 0 : currentVolume
      case "inputVolume":
        return isInputMuted ? 0 : currentInputVolume
      case "brightness":
        return currentBrightness
      default:
        return 0
      }
    }

    function getMaxValue() {
      if (currentOSDType === "volume" || currentOSDType === "inputVolume") {
        return Settings.data.audio.volumeOverdrive ? 1.5 : 1.0
      }
      return 1.0
    }

    function getDisplayPercentage() {
      const value = getCurrentValue()
      const max = getMaxValue()
      const pct = Math.round(Math.min(max, value) * 100)
      return pct + "%"
    }

    function getProgressColor() {
      const isMutedState = (currentOSDType === "volume" && isMuted) || (currentOSDType === "inputVolume" && isInputMuted)
      return isMutedState ? Color.mError : Color.mPrimary
    }

    function getIconColor() {
      const isMutedState = (currentOSDType === "volume" && isMuted) || (currentOSDType === "inputVolume" && isInputMuted)
      return isMutedState ? Color.mError : Color.mOnSurface
    }

    // ============================================================================
    // Audio Initialization
    // ============================================================================
    function initializeAudioValues() {
      // Initialize output volume
      if (AudioService.sink?.ready && AudioService.sink?.audio && lastKnownVolume < 0) {
        const vol = AudioService.volume
        if (vol !== undefined && !isNaN(vol)) {
          lastKnownVolume = vol
          volumeInitialized = true
          muteInitialized = true
        }
      }

      // Initialize input volume
      if (AudioService.hasInput && AudioService.source?.ready && AudioService.source?.audio && lastKnownInputVolume < 0) {
        const inputVol = AudioService.inputVolume
        if (inputVol !== undefined && !isNaN(inputVol)) {
          lastKnownInputVolume = inputVol
          inputInitialized = true
        }
      }
    }

    function resetOutputInit() {
      lastKnownVolume = -1
      volumeInitialized = false
      muteInitialized = false
      Qt.callLater(initializeAudioValues)
    }

    function resetInputInit() {
      lastKnownInputVolume = -1
      inputInitialized = false
      Qt.callLater(initializeAudioValues)
    }

    // ============================================================================
    // Brightness Handling
    // ============================================================================
    function connectBrightnessMonitors() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        const monitor = BrightnessService.monitors[i]
        monitor.brightnessUpdated.disconnect(onBrightnessChanged)
        monitor.brightnessUpdated.connect(onBrightnessChanged)
      }
    }

    function onBrightnessChanged(newBrightness) {
      lastUpdatedBrightness = newBrightness

      if (!brightnessInitialized) {
        brightnessInitialized = true
        return
      }

      showOSD("brightness")
    }

    // ============================================================================
    // OSD Display Control
    // ============================================================================
    function showOSD(type) {
      currentOSDType = type

      if (!root.active) {
        root.active = true
      }

      if (root.item) {
        root.item.showOSD()
      } else {
        Qt.callLater(() => {
                       if (root.item)
                       root.item.showOSD()
                     })
      }
    }

    function hideOSD() {
      if (root.item?.osdItem) {
        root.item.osdItem.hideImmediately()
      } else if (root.active) {
        root.active = false
      }
    }

    // ============================================================================
    // Signal Connections
    // ============================================================================

    // Pipewire state monitoring
    Connections {
      target: Pipewire

      function onReadyChanged() {
        if (Pipewire.ready)
          Qt.callLater(initializeAudioValues)
      }

      function onDefaultAudioSinkChanged() {
        resetOutputInit()
      }

      function onDefaultAudioSourceChanged() {
        resetInputInit()
      }
    }

    // AudioService monitoring
    Connections {
      target: AudioService

      function onSinkChanged() {
        if (AudioService.sink?.ready && AudioService.sink?.audio) {
          resetOutputInit()
        }
      }

      function onSourceChanged() {
        if (AudioService.hasInput && AudioService.source?.ready && AudioService.source?.audio) {
          resetInputInit()
        }
      }

      function onVolumeChanged() {
        if (lastKnownVolume < 0) {
          initializeAudioValues()
          if (lastKnownVolume < 0)
            return
        }
        if (!volumeInitialized)
          return

        if (Math.abs(AudioService.volume - lastKnownVolume) > 0.001) {
          lastKnownVolume = AudioService.volume
          showOSD("volume")
        }
      }

      function onMutedChanged() {
        if (lastKnownVolume < 0) {
          initializeAudioValues()
          if (lastKnownVolume < 0)
            return
        }
        if (!muteInitialized)
          return
        showOSD("volume")
      }

      function onInputVolumeChanged() {
        if (!AudioService.hasInput)
          return

        if (lastKnownInputVolume < 0) {
          initializeAudioValues()
          if (lastKnownInputVolume < 0)
            return
        }
        if (!inputInitialized)
          return

        if (Math.abs(AudioService.inputVolume - lastKnownInputVolume) > 0.001) {
          lastKnownInputVolume = AudioService.inputVolume
          showOSD("inputVolume")
        }
      }

      function onInputMutedChanged() {
        if (!AudioService.hasInput)
          return

        if (lastKnownInputVolume < 0) {
          initializeAudioValues()
          if (lastKnownInputVolume < 0)
            return
        }
        if (!inputInitialized)
          return
        showOSD("inputVolume")
      }
    }

    // Brightness monitoring
    Connections {
      target: BrightnessService
      function onMonitorsChanged() {
        connectBrightnessMonitors()
      }
    }

    // Initialization timers
    Timer {
      id: initTimer
      interval: 500
      running: true
      onTriggered: {
        if (Pipewire.ready)
          initializeAudioValues()
        muteInitialized = true
        connectBrightnessMonitors()
      }
    }

    Timer {
      id: reinitTimer
      interval: 1000
      running: true
      repeat: true
      onTriggered: {
        if (!Pipewire.ready)
          return

        const needsOutputInit = lastKnownVolume < 0
        const needsInputInit = AudioService.hasInput && lastKnownInputVolume < 0

        if (needsOutputInit || needsInputInit) {
          initializeAudioValues()

          // Stop timer if both are initialized
          const outputDone = lastKnownVolume >= 0
          const inputDone = !AudioService.hasInput || lastKnownInputVolume >= 0
          if (outputDone && inputDone) {
            running = false
          }
        } else {
          running = false
        }
      }
    }

    // ============================================================================
    // Visual Component
    // ============================================================================
    sourceComponent: PanelWindow {
      id: panel
      screen: modelData

      // Position configuration
      readonly property string location: Settings.data.osd?.location || "top_right"
      readonly property bool isTop: location === "top" || location.startsWith("top")
      readonly property bool isBottom: location === "bottom" || location.startsWith("bottom")
      readonly property bool isLeft: location.includes("_left") || location === "left"
      readonly property bool isRight: location.includes("_right") || location === "right"
      readonly property bool verticalMode: location === "left" || location === "right"

      // Dimensions
      readonly property int hWidth: Math.round(320 * Style.uiScaleRatio)
      readonly property int hHeight: Math.round(72 * Style.uiScaleRatio)
      readonly property int vWidth: Math.round(72 * Style.uiScaleRatio)
      readonly property int vHeight: Math.round(280 * Style.uiScaleRatio)
      readonly property int barThickness: {
        const base = Math.max(8, Math.round(8 * Style.uiScaleRatio))
        return base % 2 === 0 ? base : base + 1
      }

      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      function calculateMargin(isAnchored, position) {
        if (!isAnchored)
          return 0

        let base = Style.marginM
        if (Settings.data.bar.position === position) {
          const isVertical = position === "top" || position === "bottom"
          const floatExtra = Settings.data.bar.floating ? (isVertical ? Settings.data.bar.marginVertical : Settings.data.bar.marginHorizontal) * Style.marginXL : 0
          return Style.barHeight + base + floatExtra
        }
        return base
      }

      margins.top: calculateMargin(anchors.top, "top")
      margins.bottom: calculateMargin(anchors.bottom, "bottom")
      margins.left: calculateMargin(anchors.left, "left")
      margins.right: calculateMargin(anchors.right, "right")

      implicitWidth: verticalMode ? vWidth : hWidth
      implicitHeight: verticalMode ? vHeight : hHeight
      color: Color.transparent

      WlrLayershell.namespace: "noctalia-osd-" + (screen?.name || "unknown")
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.layer: Settings.data.osd?.overlayLayer ? WlrLayer.Overlay : WlrLayer.Top
      exclusionMode: PanelWindow.ExclusionMode.Ignore

      Item {
        id: osdItem
        anchors.fill: parent
        visible: false
        opacity: 0
        scale: 0.85

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Timer {
          id: hideTimer
          interval: Settings.data.osd.autoHideMs
          onTriggered: osdItem.hide()
        }

        Timer {
          id: visibilityTimer
          interval: Style.animationNormal + 50
          onTriggered: {
            osdItem.visible = false
            root.currentOSDType = ""
            root.active = false
          }
        }

        Rectangle {
          id: background
          anchors.fill: parent
          anchors.margins: Style.marginM * 1.5
          radius: Style.radiusL
          color: Qt.alpha(Color.mSurface, Settings.data.osd.backgroundOpacity || 1.0)
          border.color: Qt.alpha(Color.mOutline, Settings.data.osd.backgroundOpacity || 1.0)
          border.width: {
            const bw = Math.max(2, Style.borderM)
            return bw % 2 === 0 ? bw : bw + 1
          }
        }

        NDropShadows {
          anchors.fill: background
          source: background
          autoPaddingEnabled: true
        }

        Loader {
          id: contentLoader
          anchors.fill: background
          anchors.margins: Style.marginM
          active: true
          sourceComponent: panel.verticalMode ? verticalContent : horizontalContent
        }

        Component {
          id: horizontalContent
          RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.marginL
            spacing: Style.marginM

            NIcon {
              icon: root.getIcon()
              color: root.getIconColor()
              pointSize: Style.fontSizeXL
              Layout.alignment: Qt.AlignVCenter

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationNormal
                  easing.type: Easing.InOutQuad
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: panel.barThickness
              radius: Math.round(panel.barThickness / 2)
              color: Color.mSurfaceVariant

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1.0, root.getCurrentValue() / root.getMaxValue())
                radius: parent.radius
                color: root.getProgressColor()

                Behavior on width {
                  NumberAnimation {
                    duration: Style.animationNormal
                    easing.type: Easing.InOutQuad
                  }
                }

                Behavior on color {
                  ColorAnimation {
                    duration: Style.animationNormal
                    easing.type: Easing.InOutQuad
                  }
                }
              }
            }

            NText {
              text: root.getDisplayPercentage()
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              family: Settings.data.ui.fontFixed
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              horizontalAlignment: Text.AlignRight
              verticalAlignment: Text.AlignVCenter
              Layout.preferredWidth: Math.round(50 * Style.uiScaleRatio)
            }
          }
        }

        Component {
          id: verticalContent
          ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: Style.marginL
            anchors.bottomMargin: Style.marginL
            spacing: Style.marginS

            NText {
              text: root.getDisplayPercentage()
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              family: Settings.data.ui.fontFixed
              Layout.fillWidth: true
              Layout.preferredHeight: Math.round(20 * Style.uiScaleRatio)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: panel.barThickness
                radius: Math.round(panel.barThickness / 2)
                color: Color.mSurfaceVariant

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: parent.height * Math.min(1.0, root.getCurrentValue() / root.getMaxValue())
                  radius: parent.radius
                  color: root.getProgressColor()

                  Behavior on height {
                    NumberAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.InOutQuad
                    }
                  }

                  Behavior on color {
                    ColorAnimation {
                      duration: Style.animationNormal
                      easing.type: Easing.InOutQuad
                    }
                  }
                }
              }
            }

            NIcon {
              icon: root.getIcon()
              color: root.getIconColor()
              pointSize: Style.fontSizeL
              Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationNormal
                  easing.type: Easing.InOutQuad
                }
              }
            }
          }
        }

        function show() {
          hideTimer.stop()
          visibilityTimer.stop()
          osdItem.visible = true

          Qt.callLater(() => {
                         osdItem.opacity = 1
                         osdItem.scale = 1.0
                       })

          hideTimer.start()
        }

        function hide() {
          hideTimer.stop()
          visibilityTimer.stop()
          osdItem.opacity = 0
          osdItem.scale = 0.85
          visibilityTimer.start()
        }

        function hideImmediately() {
          hideTimer.stop()
          visibilityTimer.stop()
          osdItem.opacity = 0
          osdItem.scale = 0.85
          osdItem.visible = false
          root.currentOSDType = ""
          root.active = false
        }
      }

      function showOSD() {
        osdItem.show()
      }
    }
  }
}
