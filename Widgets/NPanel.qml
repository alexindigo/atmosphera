import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  active: false
  asynchronous: true

  property ShellScreen screen
  readonly property real scaling: screen ? ScalingService.scale(screen) : 1.0

  property Component panelContent: null
  property int panelWidth: 1500
  property int panelHeight: 400
  property color panelBackgroundColor: Color.mSurface

  property bool panelAnchorHorizontalCenter: false
  property bool panelAnchorVerticalCenter: false
  property bool panelAnchorTop: false
  property bool panelAnchorBottom: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false

  // Properties to support positioning relative to the opener (button)
  property bool useButtonPosition: false
  property point buttonPosition: Qt.point(0, 0)
  property int buttonWidth: 0
  property int buttonHeight: 0

  // Animation properties
  readonly property real originalScale: 0.7
  readonly property real originalOpacity: 0.0
  property real scaleValue: originalScale
  property real opacityValue: originalOpacity

  property alias isClosing: hideTimer.running
  readonly property real barHeight: Style.barHeight * scaling
  readonly property bool barAtBottom: Settings.data.bar.position === "bottom"

  // Helper function to check if bar is enabled on this screen
  function isBarEnabled(screen) {
    if (!screen || !screen.name)
      return false
    return Settings.data.bar.monitors.includes(screen.name) || (Settings.data.bar.monitors.length === 0)
  }

  // Helper function to get effective bar height (accounting for opacity)
  function getEffectiveBarHeight(screen) {
    if (!isBarEnabled(screen))
      return 0
    // If bar opacity is 0, treat it as if bar is not there for dimming purposes
    return Settings.data.bar.backgroundOpacity > 0 ? barHeight : 0
  }

  signal opened
  signal closed

  Component.onCompleted: {
    PanelService.registerPanel(root)
  }

  // -----------------------------------------
  function toggle(aScreen, buttonItem) {
    // Don't toggle if screen is null or invalid
    if (!aScreen || !aScreen.name) {
      Logger.warn("NPanel", "Cannot toggle panel: invalid screen object")
      return
    }

    if (!active || isClosing) {
      open(aScreen, buttonItem)
    } else {
      close()
    }
  }

  // -----------------------------------------
  function open(aScreen, buttonItem) {
    // Don't open if screen is null or invalid
    if (!aScreen || !aScreen.name) {
      Logger.warn("NPanel", "Cannot open panel: invalid screen object")
      return
    }

    if (aScreen !== null) {
      screen = aScreen
    }

    // Get t button position if provided
    if (buttonItem !== undefined && buttonItem !== null) {
      useButtonPosition = true

      var itemPos = buttonItem.mapToItem(null, 0, 0)
      buttonPosition = Qt.point(itemPos.x, itemPos.y)
      buttonWidth = buttonItem.width
      buttonHeight = buttonItem.height
    } else {
      useButtonPosition = false
    }

    // Special case if currently closing/animating
    if (isClosing) {
      hideTimer.stop() // in case we were closing
      scaleValue = 1.0
      opacityValue = 1.0
    }

    PanelService.willOpenPanel(root)

    active = true
    root.opened()
  }

  // -----------------------------------------
  function close() {
    scaleValue = originalScale
    opacityValue = originalOpacity
    hideTimer.start()
  }

  // -----------------------------------------
  function closeCompleted() {
    root.closed()
    active = false
    useButtonPosition = false // Reset button position usage
  }

  // -----------------------------------------
  // Timer to disable the loader after the close animation is completed
  Timer {
    id: hideTimer
    interval: Style.animationSlow
    repeat: false
    onTriggered: {
      closeCompleted()
    }
  }

  // -----------------------------------------
  sourceComponent: Component {
    PanelWindow {
      id: panelWindow

      visible: true

      // Dim desktop if required - but exclude corners if screen corners are enabled
      color: Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-panel"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true
      margins.top: !barAtBottom ? getEffectiveBarHeight(screen) : 0
      margins.bottom: barAtBottom ? getEffectiveBarHeight(screen) : 0

      // Close any panel with Esc without requiring focus
      Shortcut {
        sequences: ["Escape"]
        enabled: root.active && !root.isClosing
        onActivated: root.close()
        context: Qt.WindowShortcut
      }

      // Clicking outside of the rectangle to close
      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }

      // Dim overlay that excludes corners when screen corners are enabled
      Item {
        id: dimOverlay
        anchors.fill: parent
        visible: root.active && !root.isClosing && Settings.data.general.dimDesktop
        opacity: visible ? 1.0 : 0.0

        // Helper function to check if screen corners are enabled
        function isScreenCornersEnabled() {
          return Settings.data.general.showScreenCorners
        }

        // Helper function to get corner radius
        function getCornerRadius() {
          return 20 // Same as ScreenCorners innerRadius
        }

        // Helper function to get border width
        function getBorderWidth() {
          return Style.borderM
        }

        // Full screen dim when screen corners are disabled
        Rectangle {
          id: fullScreenDim
          visible: dimOverlay.visible && !dimOverlay.isScreenCornersEnabled()
          anchors.fill: parent
          color: Color.applyOpacity(Color.mShadow, "BB")
        }

        // Masked dim when screen corners are enabled
        Item {
          id: maskedDim
          visible: dimOverlay.visible && dimOverlay.isScreenCornersEnabled()
          anchors.fill: parent

          // Only dim the center area, leaving the entire border undimmed
          Rectangle {
            id: centerDim
            anchors.margins: dimOverlay.getCornerRadius() + dimOverlay.getBorderWidth()
            anchors.fill: parent
            color: Color.applyOpacity(Color.mShadow, "BB")
          }
        }

        // Behavior for dim overlay visibility
        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
          }
        }
      }

      Rectangle {
        id: panelBackground
        color: panelBackgroundColor
        radius: Style.radiusL * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        layer.enabled: true
        width: panelWidth
        height: panelHeight

        scale: root.scaleValue
        opacity: root.opacityValue

        x: calculatedX
        y: calculatedY

        property int calculatedX: {
          if (root.useButtonPosition) {
            // Position panel relative to button
            var targetX = root.buttonPosition.x + (root.buttonWidth / 2) - (panelWidth / 2)

            // Keep panel within screen bounds
            var maxX = panelWindow.width - panelWidth - (Style.marginS * scaling)
            var minX = Style.marginS * scaling

            return Math.max(minX, Math.min(targetX, maxX))
          } else if (!panelAnchorHorizontalCenter && panelAnchorLeft) {
            return Style.marginS * scaling
          } else if (!panelAnchorHorizontalCenter && panelAnchorRight) {
            return panelWindow.width - panelWidth - (Style.marginS * scaling)
          } else {
            return (panelWindow.width - panelWidth) / 2
          }
        }

        property int calculatedY: {
          if (panelAnchorVerticalCenter) {
            return (panelWindow.height - panelHeight) / 2
          } else if (panelAnchorBottom) {
            return panelWindow.height - panelHeight - (Style.marginS * scaling)
          } else if (panelAnchorTop) {
            return (Style.marginS * scaling)
          } else if (panelAnchorBottom) {
            panelWindow.height - panelHeight - (Style.marginS * scaling)
          } else if (!barAtBottom) {
            // Below the top bar
            return Style.marginS * scaling
          } else {
            // Above the bottom bar
            return panelWindow.height - panelHeight - (Style.marginS * scaling)
          }
        }

        // Animate in when component is completed
        Component.onCompleted: {
          root.scaleValue = 1.0
          root.opacityValue = 1.0
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
          anchors.fill: parent
        }

        // Animation behaviors
        Behavior on scale {
          NumberAnimation {
            duration: Style.animationSlow
            easing.type: Easing.OutExpo
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }

        Loader {
          anchors.fill: parent
          sourceComponent: root.panelContent
        }
      }
    }
  }
}
