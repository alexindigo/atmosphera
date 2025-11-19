import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Hardware
import qs.Services.Media
import qs.Widgets

// Unified OSD component that displays volume, input volume, and brightness changes
Variants {
  model: Quickshell.screens.filter(screen => (Settings.data.osd.monitors.includes(screen.name) || Settings.data.osd.monitors.length === 0) && Settings.data.osd.enabled)

  delegate: Loader {
    id: root

    required property ShellScreen modelData

    active: false

    // OSD State
    property string currentOSDType: "" // "volume", "inputVolume", "brightness", or ""
    property bool startupComplete: false
    property real currentBrightness: 0

    // Current values (computed properties)
    readonly property real currentVolume: AudioService.volume
    readonly property bool isMuted: AudioService.muted
    readonly property real currentInputVolume: AudioService.inputVolume
    readonly property bool isInputMuted: AudioService.inputMuted

    // ============================================================================
    // Helper Functions
    // ============================================================================
    function getIcon() {
      switch (currentOSDType) {
      case "volume":
        if (isMuted)
          return "volume-mute";
        if (currentVolume <= Number.EPSILON)
          return "volume-zero";
        return currentVolume <= 0.5 ? "volume-low" : "volume-high";
      case "inputVolume":
        return isInputMuted ? "microphone-off" : "microphone";
      case "brightness":
        return currentBrightness <= 0.5 ? "brightness-low" : "brightness-high";
      default:
        return "";
      }
    }

    function getCurrentValue() {
      switch (currentOSDType) {
      case "volume":
        return isMuted ? 0 : currentVolume;
      case "inputVolume":
        return isInputMuted ? 0 : currentInputVolume;
      case "brightness":
        return currentBrightness;
      default:
        return 0;
      }
    }

    function getMaxValue() {
      if (currentOSDType === "volume" || currentOSDType === "inputVolume") {
        return Settings.data.audio.volumeOverdrive ? 1.5 : 1.0;
      }
      return 1.0;
    }

    function getDisplayPercentage() {
      const value = getCurrentValue();
      const max = getMaxValue();
      if ((currentOSDType === "volume" || currentOSDType === "inputVolume") && Settings.data.audio.volumeOverdrive) {
        const pct = Math.round(value * 100);
        return pct + "%";
      }
      const pct = Math.round(Math.min(max, value) * 100);
      return pct + "%";
    }

    function getProgressColor() {
      const isMutedState = (currentOSDType === "volume" && isMuted) || (currentOSDType === "inputVolume" && isInputMuted);
      if (isMutedState) {
        return Color.mError;
      }
      // When volumeOverdrive is enabled, show error color if volume is above 100%
      if ((currentOSDType === "volume" || currentOSDType === "inputVolume") && Settings.data.audio.volumeOverdrive) {
        const value = getCurrentValue();
        if (value > 1.0) {
          return Color.mError;
        }
      }
      return Color.mPrimary;
    }

    function getIconColor() {
      const isMutedState = (currentOSDType === "volume" && isMuted) || (currentOSDType === "inputVolume" && isInputMuted);
      return isMutedState ? Color.mError : Color.mOnSurface;
    }

    // ============================================================================
    // Brightness Handling
    // ============================================================================
    function connectBrightnessMonitors() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        const monitor = BrightnessService.monitors[i];
        monitor.brightnessUpdated.disconnect(onBrightnessChanged);
        monitor.brightnessUpdated.connect(onBrightnessChanged);
      }
    }

    function onBrightnessChanged(newBrightness) {
      currentBrightness = newBrightness;
      showOSD("brightness");
    }

    // ============================================================================
    // OSD Display Control
    // ============================================================================
    function showOSD(type) {
      // Ignore all OSD requests during startup period
      if (!startupComplete)
        return;

      currentOSDType = type;

      if (!root.active) {
        root.active = true;
      }

      if (root.item) {
        root.item.showOSD();
      } else {
        Qt.callLater(() => {
                       if (root.item)
                       root.item.showOSD();
                     });
      }
    }

    function hideOSD() {
      if (root.item?.osdItem) {
        root.item.osdItem.hideImmediately();
      } else if (root.active) {
        root.active = false;
      }
    }

    // ============================================================================
    // Signal Connections
    // ============================================================================

    // AudioService monitoring
    Connections {
      target: AudioService

      function onVolumeChanged() {
        showOSD("volume");
      }

      function onMutedChanged() {
        showOSD("volume");
      }

      function onInputVolumeChanged() {
        if (AudioService.hasInput)
          showOSD("inputVolume");
      }

      function onInputMutedChanged() {
        if (AudioService.hasInput)
          showOSD("inputVolume");
      }
    }

    // Brightness monitoring
    Connections {
      target: BrightnessService
      function onMonitorsChanged() {
        connectBrightnessMonitors();
      }
    }

    // Startup timer - connect brightness monitors and enable OSD after 2 seconds
    Timer {
      id: startupTimer
      interval: 2000
      running: true
      onTriggered: {
        connectBrightnessMonitors();
        root.startupComplete = true;
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
      readonly property int vWidth: Math.round(80 * Style.uiScaleRatio)
      readonly property int vHeight: Math.round(280 * Style.uiScaleRatio)
      readonly property int barThickness: {
        const base = Math.max(8, Math.round(8 * Style.uiScaleRatio));
        return base % 2 === 0 ? base : base + 1;
      }

      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      function calculateMargin(isAnchored, position) {
        if (!isAnchored)
          return 0;

        let base = Style.marginM;
        if (Settings.data.bar.position === position) {
          const isVertical = position === "top" || position === "bottom";
          const floatExtra = Settings.data.bar.floating ? (isVertical ? Settings.data.bar.marginVertical : Settings.data.bar.marginHorizontal) * Style.marginXL : 0;
          return Style.barHeight + base + floatExtra;
        }
        return base;
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
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

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
            osdItem.visible = false;
            root.currentOSDType = "";
            root.active = false;
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
            const bw = Math.max(2, Style.borderM);
            return bw % 2 === 0 ? bw : bw + 1;
          }
        }

        NDropShadow {
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
            anchors.fill: parent
            anchors.leftMargin: Style.marginL
            anchors.rightMargin: Style.marginL
            spacing: Style.marginM
            clip: true

            // TextMetrics to measure the maximum possible percentage width (150%)
            TextMetrics {
              id: percentageMetrics
              font.family: Settings.data.ui.fontFixed
              font.weight: Style.fontWeightMedium
              font.pointSize: Style.fontSizeS * (Settings.data.ui.fontFixedScale * Style.uiScaleRatio)
              text: "150%" // Maximum possible value with volumeOverdrive
            }

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
              Layout.alignment: Qt.AlignVCenter
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
              Layout.fillWidth: false
              Layout.preferredWidth: Math.ceil(percentageMetrics.width) + Math.round(8 * Style.uiScaleRatio)
              Layout.maximumWidth: Math.ceil(percentageMetrics.width) + Math.round(8 * Style.uiScaleRatio)
              Layout.minimumWidth: Math.ceil(percentageMetrics.width)
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
            clip: true

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
          hideTimer.stop();
          visibilityTimer.stop();
          osdItem.visible = true;

          Qt.callLater(() => {
                         osdItem.opacity = 1;
                         osdItem.scale = 1.0;
                       });

          hideTimer.start();
        }

        function hide() {
          hideTimer.stop();
          visibilityTimer.stop();
          osdItem.opacity = 0;
          osdItem.scale = 0.85;
          visibilityTimer.start();
        }

        function hideImmediately() {
          hideTimer.stop();
          visibilityTimer.stop();
          osdItem.opacity = 0;
          osdItem.scale = 0.85;
          osdItem.visible = false;
          root.currentOSDType = "";
          root.active = false;
        }
      }

      function showOSD() {
        osdItem.show();
      }
    }
  }
}
