import QtQuick
import Quickshell
import Quickshell.Wayland

// An unmistakable desktop-only overlay. ext-session-lock must cover this,
// including the interval after the emergency holder dies without unlocking.
ShellRoot {
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusiveZone: -1
      color: "#ff00ff"
      Text {
        anchors.centerIn: parent
        text: "UNLOCKED DESKTOP SENTINEL"
        color: "#00ff00"
        font.pixelSize: 40
      }
    }
  }
}
