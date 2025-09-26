import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

// Unified OSD component - handles both volume and brightness with a single instance
// Loader activates only when showing OSD, deactivates when hidden to save resources
Variants {
  model: Quickshell.screens

  delegate: Loader {
    id: root

    required property ShellScreen modelData
    property real scaling: ScalingService.getScreenScale(modelData)

    // Access the notification model from the service
    property ListModel notificationModel: NotificationService.activeList

    // If no notification display activated in settings, then show them all
    property bool canShowOnThisScreen: Settings.isLoaded && modelData && (Settings.data.notifications.monitors.includes(modelData.name) || (Settings.data.notifications.monitors.length === 0))

    // Loader is only active when actually showing something
    active: false

    // Current OSD display state
    property string currentOSDType: "" // "volume", "brightness", or ""

    // Volume properties
    readonly property real currentVolume: AudioService.volume
    readonly property bool isMuted: AudioService.muted
    property bool volumeInitialized: false
    property bool muteInitialized: false

    // Brightness properties
    property bool brightnessInitialized: false
    readonly property real currentBrightness: {
      if (BrightnessService.monitors.length > 0) {
        return BrightnessService.monitors[0].brightness || 0
      }
      return 0
    }

    // Get appropriate icon based on current OSD type
    function getIcon() {
      if (currentOSDType === "volume") {
        if (AudioService.muted) {
          return "volume-mute"
        }
        return (AudioService.volume <= Number.EPSILON) ? "volume-zero" : (AudioService.volume <= 0.5) ? "volume-low" : "volume-high"
      } else if (currentOSDType === "brightness") {
        return currentBrightness <= 0.5 ? "brightness-low" : "brightness-high"
      }
      return ""
    }

    // Get current value (0-1 range)
    function getCurrentValue() {
      if (currentOSDType === "volume") {
        return isMuted ? 0 : currentVolume
      } else if (currentOSDType === "brightness") {
        return currentBrightness
      }
      return 0
    }

    // Get display percentage
    function getDisplayPercentage() {
      if (currentOSDType === "volume") {
        return isMuted ? "0%" : Math.round(currentVolume * 100) + "%"
      } else if (currentOSDType === "brightness") {
        return Math.round(currentBrightness * 100) + "%"
      }
      return ""
    }

    // Get progress bar color
    function getProgressColor() {
      if (currentOSDType === "volume") {
        if (isMuted)
          return Color.mError
        if (currentVolume > 1.0)
          return Color.mError
        return Color.mPrimary
      }
      return Color.mPrimary
    }

    // Get icon color
    function getIconColor() {
      if (currentOSDType === "volume" && isMuted) {
        return Color.mError
      }
      return Color.mOnSurface
    }

    sourceComponent: PanelWindow {
      screen: modelData

      readonly property string location: (Settings.isLoaded && Settings.data && Settings.data.notifications && Settings.data.notifications.location) ? Settings.data.notifications.location : "top_right"
      readonly property bool isTop: (location === "top") || (location.length >= 3 && location.substring(0, 3) === "top")
      readonly property bool isBottom: (location === "bottom") || (location.length >= 6 && location.substring(0, 6) === "bottom")
      readonly property bool isLeft: location.indexOf("_left") >= 0
      readonly property bool isRight: location.indexOf("_right") >= 0
      readonly property bool isCentered: (location === "top" || location === "bottom")

      // Anchor selection based on location (window edges)
      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      // Margins depending on bar position and chosen location
      margins.top: {
        if (!(anchors.top))
          return 0
        var base = Style.marginM * scaling
        if (Settings.data.bar.position === "top") {
          var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0
          return (Style.barHeight * scaling) + base + floatExtraV
        }
        return base
      }

      margins.bottom: {
        if (!(anchors.bottom))
          return 0
        var base = Style.marginM * scaling
        if (Settings.data.bar.position === "bottom") {
          var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0
          return (Style.barHeight * scaling) + base + floatExtraV
        }
        return base
      }

      margins.left: {
        if (!(anchors.left))
          return 0
        var base = Style.marginM * scaling
        if (Settings.data.bar.position === "left") {
          var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling : 0
          return (Style.barHeight * scaling) + base + floatExtraH
        }
        return base
      }

      margins.right: {
        if (!(anchors.right))
          return 0
        var base = Style.marginM * scaling
        if (Settings.data.bar.position === "right") {
          var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling : 0
          return (Style.barHeight * scaling) + base + floatExtraH
        }
        return base
      }

      implicitWidth: 320 * root.scaling
      implicitHeight: osdItem.height

      color: Color.transparent

      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: PanelWindow.ExclusionMode.Ignore

      Rectangle {
        id: osdItem

        width: parent.width
        height: Math.round(contentLayout.implicitHeight + Style.marginL * 2 * root.scaling)
        radius: Style.radiusL * root.scaling
        color: Color.mSurface
        border.color: Color.mOutline
        border.width: Math.max(2, Style.borderM * root.scaling)
        visible: false
        opacity: 0
        scale: 0.85

        anchors.horizontalCenter: parent.horizontalCenter

        Behavior on opacity {
          NumberAnimation {
            id: opacityAnimation
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Behavior on scale {
          NumberAnimation {
            id: scaleAnimation
            duration: Style.animationNormal
            easing.type: Easing.InOutQuad
          }
        }

        Timer {
          id: hideTimer
          interval: 2000
          onTriggered: osdItem.hide()
        }

        // Timer to handle visibility after animations complete
        Timer {
          id: visibilityTimer
          interval: Style.animationNormal + 50 // Add small buffer
          onTriggered: {
            osdItem.visible = false
            root.currentOSDType = ""
            // Deactivate the loader when done
            root.active = false
          }
        }

        RowLayout {
          id: contentLayout
          anchors.fill: parent
          anchors.margins: Style.marginM * root.scaling
          spacing: Style.marginM * root.scaling

          NIcon {
            icon: root.getIcon()
            color: root.getIconColor()
            font.pointSize: Style.fontSizeXL * root.scaling
            Layout.alignment: Qt.AlignVCenter

            // Smooth icon transitions
            Behavior on color {
              ColorAnimation {
                duration: Style.animationNormal
                easing.type: Easing.InOutQuad
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.marginXS * root.scaling

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.round(6 * root.scaling)
              radius: Math.round(3 * root.scaling)
              color: Color.mSurfaceVariant

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1.0, root.getCurrentValue())
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
              font.pointSize: Style.fontSizeS * root.scaling
              Layout.alignment: Qt.AlignVCenter
              Layout.minimumWidth: Math.round(32 * root.scaling)
            }
          }
        }

        function show() {
          // Cancel any pending hide operations
          hideTimer.stop()
          visibilityTimer.stop()

          // Make visible and animate in
          osdItem.visible = true
          // Use Qt.callLater to ensure the visible change is processed before animation
          Qt.callLater(function () {
            osdItem.opacity = 1
            osdItem.scale = 1.0
          })

          // Start the auto-hide timer
          hideTimer.start()
        }

        function hide() {
          hideTimer.stop()
          visibilityTimer.stop()

          // Start fade out animation
          osdItem.opacity = 0
          osdItem.scale = 0.85 // Less dramatic scale change for smoother effect

          // Delay hiding the element until after animation completes
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

    // Volume change monitoring
    Connections {
      target: AudioService

      function onVolumeChanged() {
        if (volumeInitialized) {
          showOSD("volume")
        }
      }

      function onMutedChanged() {
        if (muteInitialized) {
          showOSD("volume")
        }
      }
    }

    // Timer to initialize volume/mute flags after services are ready
    Timer {
      id: initTimer
      interval: 500
      running: true
      onTriggered: {
        volumeInitialized = true
        muteInitialized = true
      }
    }

    // Brightness change monitoring
    Connections {
      target: BrightnessService

      function onMonitorsChanged() {
        connectBrightnessMonitors()
      }
    }

    Component.onCompleted: {
      connectBrightnessMonitors()
    }

    function connectBrightnessMonitors() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        let monitor = BrightnessService.monitors[i]
        // Disconnect first to avoid duplicate connections
        monitor.brightnessUpdated.disconnect(onBrightnessChanged)
        monitor.brightnessUpdated.connect(onBrightnessChanged)
      }
    }

    function onBrightnessChanged(newBrightness) {
      if (!brightnessInitialized) {
        brightnessInitialized = true
      } else {
        showOSD("brightness")
      }
    }

    function showOSD(type) {
      // Check if OSD is enabled in settings and can show on this screen
      if (!Settings.data.notifications.enableOSD || !canShowOnThisScreen) {
        return
      }

      // Update the current OSD type
      currentOSDType = type

      // Activate the loader if not already active
      if (!root.active) {
        root.active = true
      }

      // Show the OSD (may need to wait for loader to create the item)
      if (root.item) {
        root.item.showOSD()
      } else {
        // If item not ready yet, wait for it
        Qt.callLater(function () {
          if (root.item) {
            root.item.showOSD()
          }
        })
      }
    }

    function hideOSD() {
      if (root.item && root.item.osdItem) {
        root.item.osdItem.hideImmediately()
      } else if (root.active) {
        // If loader is active but item isn't ready, just deactivate
        root.active = false
      }
    }
  }
}
