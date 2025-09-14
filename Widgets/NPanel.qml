import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  property Component panelContent: null
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
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
  readonly property string barPosition: Settings.data.bar.position

  signal opened
  signal closed

  active: false
  asynchronous: true

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
  function toggle(buttonItem) {
    if (!active || isClosing) {
      open(buttonItem)
    } else {
      close()
    }
  }

  // -----------------------------------------
  function open(buttonItem) {
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

      // PanelWindow has its own screen property inherited of QsWindow
      property real scaling: ScalingService.getScreenScale(screen)
      readonly property real barHeight: Math.round(Style.barHeight * scaling)
      readonly property real barWidth: Math.round(Style.barHeight * scaling)
      readonly property bool barAtBottom: Settings.data.bar.position === "bottom"
      readonly property bool barIsVisible: (screen !== null) && (Settings.data.bar.monitors.includes(screen.name) || (Settings.data.bar.monitors.length === 0))

      Connections {
        target: ScalingService
        function onScaleChanged(screenName, scale) {
          if ((screen !== null) && (screenName === screen.name)) {
            root.scaling = scaling = scale
          }
        }
      }

      Connections {
        target: panelWindow
        function onScreenChanged() {
          root.screen = screen
          root.scaling = scaling = ScalingService.getScreenScale(screen)

          // It's mandatory to force refresh the subloader to ensure the scaling is properly dispatched
          panelContentLoader.active = false
          panelContentLoader.active = true
        }
      }

      visible: true

      // Dim desktop if required
      color: (root.active && !root.isClosing && Settings.data.general.dimDesktop) ? Qt.alpha(Color.mShadow, Style.opacityHeavy) : Color.transparent

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
      margins.top: {
        if (!barIsVisible || barAtBottom) {
          return 0
        }
        switch (Settings.data.bar.position) {
        case "top":
          return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating && !panelAnchorVerticalCenter ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0)
        default:
          return Style.marginM * scaling
        }
      }

      margins.bottom: {
        if (!barIsVisible || !barAtBottom) {
          return 0
        }
        switch (Settings.data.bar.position) {
        case "bottom":
          return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating && !panelAnchorVerticalCenter ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0)
        default:
          return 0
        }
      }

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
        width: {
          var w
          if (preferredWidthRatio !== undefined) {
            w = Math.round(Math.max(screen?.width * preferredWidthRatio, preferredWidth) * scaling)
          } else {
            w = preferredWidth * scaling
          }
          // Clamp width so it is never bigger than the screen
          return Math.min(w, screen?.width - Style.marginL * 2)
        }
        height: {
          var h
          if (preferredHeightRatio !== undefined) {
            h = Math.round(Math.max(screen?.height * preferredHeightRatio, preferredHeight) * scaling)
          } else {
            h = preferredHeight * scaling
          }

          // Clamp width so it is never bigger than the screen
          return Math.min(h, screen?.height - Style.barHeight * scaling - Style.marginL * 2)
        }

        scale: root.scaleValue
        opacity: root.opacityValue

        x: calculatedX
        y: calculatedY

        property int calculatedX: {
          var barPosition = Settings.data.bar.position

          // Check anchor properties first, even when using button positioning
          if (!panelAnchorHorizontalCenter && panelAnchorLeft) {
            return Math.round(Style.marginS * scaling)
          } else if (!panelAnchorHorizontalCenter && panelAnchorRight) {
            // For right anchor, consider bar position
            if (barPosition === "right") {
              // If bar is on right, position panel to the left of the bar
              var maxX = panelWindow.width - barWidth - panelBackground.width - (Style.marginS * scaling)

              // If we have button position, position close to the button like working panels
              if (root.useButtonPosition) {
                // Use the same logic as working panels - position at edge of bar with spacing
                var maxXWithSpacing = panelWindow.width - barWidth - panelBackground.width
                // Add spacing - more if screen corners are disabled, less if enabled
                if (!Settings.data.general.showScreenCorners || Settings.data.bar.floating) {
                  maxXWithSpacing -= Style.marginL * scaling
                } else {
                  maxXWithSpacing -= Style.marginM * scaling
                }
                return Math.round(maxXWithSpacing)
              } else {
                return Math.round(maxX)
              }
            } else {
              // Default right positioning
              var rightX = panelWindow.width - panelBackground.width - (Style.marginS * scaling)
              return Math.round(rightX)
            }
          } else if (root.useButtonPosition) {
            // Position panel relative to button (only if no explicit anchoring)
            var targetX

            // For vertical bars, position panel close to the button
            if (barPosition === "left") {
              // Position panel to the right of the left bar, close to the button
              var minX = barWidth
              // Add spacing - more if screen corners are disabled, less if enabled
              if (!Settings.data.general.showScreenCorners || Settings.data.bar.floating) {
                minX += Style.marginL * scaling
              } else {
                minX += Style.marginM * scaling
              }
              targetX = minX
            } else if (barPosition === "right") {
              // Position panel to the left of the right bar, close to the button
              var maxX = panelWindow.width - barWidth - panelBackground.width
              // Add spacing - more if screen corners are disabled, less if enabled
              if (!Settings.data.general.showScreenCorners || Settings.data.bar.floating) {
                maxX -= Style.marginL * scaling
              } else {
                maxX -= Style.marginM * scaling
              }
              targetX = maxX
            } else {
              // For horizontal bars, center panel on button
              targetX = root.buttonPosition.x + (root.buttonWidth / 2) - (panelBackground.width / 2)
            }

            // Keep panel within screen bounds
            var maxScreenX = panelWindow.width - panelBackground.width - (Style.marginS * scaling)
            var minScreenX = Style.marginS * scaling

            return Math.round(Math.max(minScreenX, Math.min(targetX, maxScreenX)))
          } else {
            // For vertical bars, center but avoid bar overlap
            var centerX = (panelWindow.width - panelBackground.width) / 2
            if (barPosition === "left") {
              var minX = barWidth
              // Add spacing - more if screen corners are disabled, less if enabled
              if (!Settings.data.general.showScreenCorners || Settings.data.bar.floating) {
                minX += Style.marginL * scaling
              } else {
                minX += Style.marginM * scaling
              }
              centerX = Math.max(centerX, minX)
            } else if (barPosition === "right") {
              // For right bar, center but ensure it doesn't overlap with the bar
              var maxX = panelWindow.width - barWidth - panelBackground.width
              // Add spacing - more if screen corners are disabled, less if enabled
              if (!Settings.data.general.showScreenCorners || Settings.data.bar.floating) {
                maxX -= Style.marginL * scaling
              } else {
                maxX -= Style.marginM * scaling
              }
              centerX = Math.min(centerX, maxX)
            }
            return Math.round(centerX)
          }
        }

        property int calculatedY: {
          var barPosition = Settings.data.bar.position

          if (root.useButtonPosition) {
            // Position panel relative to button
            var targetY = root.buttonPosition.y + (root.buttonHeight / 2) - (panelBackground.height / 2)

            // Keep panel within screen bounds
            var maxY = panelWindow.height - panelBackground.height - (Style.marginS * scaling)
            var minY = Style.marginS * scaling

            return Math.round(Math.max(minY, Math.min(targetY, maxY)))
          } else if (panelAnchorVerticalCenter) {
            return Math.round((panelWindow.height - panelBackground.height) / 2)
          } else if (panelAnchorBottom) {
            return Math.round(panelWindow.height - panelBackground.height - (Style.marginS * scaling))
          } else if (panelAnchorTop) {
            return Math.round(Style.marginS * scaling)
          } else if (barPosition === "left" || barPosition === "right") {
            // For vertical bars, center vertically
            return Math.round((panelWindow.height - panelBackground.height) / 2)
          } else if (!barAtBottom) {
            // Below the top bar
            return Math.round(Style.marginS * scaling)
          } else {
            // Above the bottom bar
            return Math.round(panelWindow.height - panelBackground.height - (Style.marginS * scaling))
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
          id: panelContentLoader
          anchors.fill: parent
          sourceComponent: root.panelContent
        }
      }
    }
  }
}
