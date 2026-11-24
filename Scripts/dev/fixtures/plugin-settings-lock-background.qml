// Independent input recipient behind the real session lock. Its native field
// proves ordinary text delivery before testing lock isolation; the toggle
// independently detects activation leaking to the unlocked desktop.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Widgets

ShellRoot {
  id: root
  property int toggles: 0
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 480
    implicitHeight: 240
    Column {
      TextField {
        id: input
        focus: true
        Component.onCompleted: forceActiveFocus()
      }
      NToggle {
        label: "Session lock input canary"
        onToggled: root.toggles++
      }
    }
  }
  IpcHandler {
    target: "lockBackground"
    function state(): string {
      return JSON.stringify({
                              length: input.length,
                              toggles: root.toggles,
                              focused: input.activeFocus
                            });
    }
    function finish() {
      Qt.quit();
    }
  }
}
