import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  active: false
  asynchronous: true

  readonly property real scaling: ScalingService.scale(screen)
  property ShellScreen screen

  property Component panelContent: null
  property int panelWidth: 1500
  property int panelHeight: 400
  property bool panelAnchorCentered: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false
  property bool panelAnchorBottomCentered: false
  property bool panelAnchorTopCentered: false
  property color panelBackgroundColor: Color.mSurface

  // Animation properties
  readonly property real originalScale: 0.7
  readonly property real originalOpacity: 0.0
  property real scaleValue: originalScale
  property real opacityValue: originalOpacity

  property alias isClosing: hideTimer.running

  signal opened
  signal closed

  Component.onCompleted: {
    PanelService.registerPanel(root)
  }

  // -----------------------------------------
  function toggle(aScreen) {
    if (!active || isClosing) {
      open(aScreen)
    } else {
      close()
    }
  }

  // -----------------------------------------
  function open(aScreen) {
    if (aScreen !== null) {
      screen = aScreen
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
      color: (root.active && !root.isClosing && Settings.data.general.dimDesktop) ? Color.applyOpacity(
                                                                                      Color.mShadow,
                                                                                      "BB") : Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-panel"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      Behavior on color {
        ColorAnimation {
          duration: Style.animationNormal
        }
      }

      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true
      margins.top: Settings.data.bar.position === "top" ? Style.barHeight * scaling : 0
      margins.bottom: Settings.data.bar.position === "bottom" ? Style.barHeight * scaling : 0

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

      Rectangle {
        id: panelBackground
        color: panelBackgroundColor
        radius: Style.radiusL * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        layer.enabled: true
        width: panelWidth
        height: panelHeight

        anchors {
          // Top/bottom centered modes
          horizontalCenter: (panelAnchorTopCentered || panelAnchorBottomCentered) ? parent.horizontalCenter : undefined
          top: panelAnchorTopCentered ? parent.top : (!panelAnchorTopCentered && !panelAnchorBottomCentered
                                                      && !panelAnchorCentered
                                                      && (Settings.data.bar.position === "top") ? parent.top : undefined)
          bottom: panelAnchorBottomCentered ? parent.bottom : ((!panelAnchorBottomCentered && !panelAnchorCentered
                                                                && (Settings.data.bar.position === "bottom")) ? parent.bottom : undefined)

          // Fully centered mode
          centerIn: (!panelAnchorTopCentered && !panelAnchorBottomCentered && panelAnchorCentered) ? parent : null

          // Side-anchored modes
          left: (!panelAnchorTopCentered && !panelAnchorBottomCentered && !panelAnchorCentered
                 && panelAnchorLeft) ? parent.left : parent.center
          right: (!panelAnchorTopCentered && !panelAnchorBottomCentered && !panelAnchorCentered
                  && panelAnchorRight) ? parent.right : parent.center

          // margins
          topMargin: panelAnchorTopCentered ? Style.marginS * scaling : (!panelAnchorBottomCentered
                                                                         && !panelAnchorCentered
                                                                         && (Settings.data.bar.position
                                                                             === "top")) ? Style.marginS * scaling : undefined
          bottomMargin: panelAnchorBottomCentered ? Style.marginS * scaling : (!panelAnchorCentered
                                                                               && (Settings.data.bar.position
                                                                                   === "bottom") ? Style.marginS * scaling : undefined)
          rightMargin: (!panelAnchorTopCentered && !panelAnchorBottomCentered && !panelAnchorCentered
                        && panelAnchorRight) ? Style.marginS * scaling : undefined
        }

        scale: root.scaleValue
        opacity: root.opacityValue

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
