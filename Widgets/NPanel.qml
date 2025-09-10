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
  property real scaling: ScalingService.getScreenScale(screen)

  Connections {
    target: ScalingService
    function onScaleChanged(screenName, scale) {
      if ((screen !== null) && (screenName === screen.name)) {
        scaling = scale
      }
    }
  }

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

  property bool panelKeyboardFocus: false
  property bool backgroundClickEnabled: true

  // Animation properties
  readonly property real originalScale: 0.7
  readonly property real originalOpacity: 0.0
  property real scaleValue: originalScale
  property real opacityValue: originalOpacity

  property alias isClosing: hideTimer.running
  readonly property real barHeight: Math.round(Style.barHeight * scaling)
  readonly property bool barAtBottom: Settings.data.bar.position === "bottom"
  readonly property bool barIsVisible: (screen !== null) && (Settings.data.bar.monitors.includes(screen.name)
                                                             || (Settings.data.bar.monitors.length === 0))

  signal opened
  signal closed

  Component.onCompleted: {
    PanelService.registerPanel(root)
  }

  // -----------------------------------------
  // Functions to control background click behavior
  function disableBackgroundClick() {
    backgroundClickEnabled = false
  }

  function enableBackgroundClick() {
    // Add a small delay to prevent immediate close after drag release
    enableBackgroundClickTimer.restart()
  }

  Timer {
    id: enableBackgroundClickTimer
    interval: 100
    repeat: false
    onTriggered: backgroundClickEnabled = true
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

    // Get the button position if provided
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

    backgroundClickEnabled = true
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
    useButtonPosition = false
    backgroundClickEnabled = true
    PanelService.closedPanel(root)
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

      // Dim desktop if required
      color: (root.active && !root.isClosing
              && Settings.data.general.dimDesktop) ? Qt.alpha(Color.mShadow, Style.opacityHeavy) : Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-panel"
      WlrLayershell.keyboardFocus: root.panelKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

      Behavior on color {
        ColorAnimation {
          duration: Style.animationNormal
        }
      }

      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true
      margins.top: (barIsVisible && !barAtBottom) ? barHeight : 0
      margins.bottom: (barIsVisible && barAtBottom) ? barHeight : 0

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
        enabled: root.backgroundClickEnabled
        onClicked: root.close()
      }

      Rectangle {
        id: panelBackground
        color: panelBackgroundColor
        radius: Style.radiusL * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
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

            return Math.round(Math.max(minX, Math.min(targetX, maxX)))
          } else if (!panelAnchorHorizontalCenter && panelAnchorLeft) {
            return Math.round(Style.marginS * scaling)
          } else if (!panelAnchorHorizontalCenter && panelAnchorRight) {
            return Math.round(panelWindow.width - panelWidth - (Style.marginS * scaling))
          } else {
            return Math.round((panelWindow.width - panelWidth) / 2)
          }
        }

        property int calculatedY: {
          if (panelAnchorVerticalCenter) {
            return Math.round((panelWindow.height - panelHeight) / 2)
          } else if (panelAnchorBottom) {
            return Math.round(panelWindow.height - panelHeight - (Style.marginS * scaling))
          } else if (panelAnchorTop) {
            return Math.round(Style.marginS * scaling)
          } else if (!barAtBottom) {
            // Below the top bar
            return Math.round(Style.marginS * scaling)
          } else {
            // Above the bottom bar
            return Math.round(panelWindow.height - panelHeight - (Style.marginS * scaling))
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
