import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Variants {
  model: Quickshell.screens

  delegate: Loader {
    required property ShellScreen modelData
    readonly property real scaling: ScalingService.scale(modelData)

    active: NightLightService.isActive

    sourceComponent: PanelWindow {
      screen: modelData
      color: Color.transparent
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      // Ensure a full click through
      mask: Region {}

      WlrLayershell.layer: WlrLayershell.Overlay
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "noctalia-nightlight"

      Rectangle {
        anchors.fill: parent
        color: NightLightService.overlayColor

        Behavior on color {
          ColorAnimation {
            duration: Style.animationSlow
          }
        }
      }
    }
  }
}
