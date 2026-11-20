// Independent real Wayland input canary. No plugin or preference writer.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root
  property int phase: 0
  property int escapes: 0
  property int clicks: 0
  readonly property string injector: Quickshell.env("PHA_INPUT_INJECTOR")
  function check(ok, message) {
    if (!ok) {
      console.error("INPUT_ASSERT: " + message);
      Qt.exit(2);
    }
  }
  Process {
    id: keys
    onExited: function (code) {
      root.check(code === 0, "injector exit");
    }
  }
  PanelWindow {
    id: window
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    implicitWidth: 500
    implicitHeight: 160
    TextField {
      id: input
      anchors.top: parent.top
      width: parent.width
      Keys.onEscapePressed: event => {
        root.escapes++;
        event.accepted = true;
      }
    }
    Button {
      id: button
      anchors.bottom: parent.bottom
      text: "Input canary"
      onClicked: root.clicks++
    }
    Popup {
      id: modal
      parent: window.contentItem
      width: 450
      height: 80
      modal: true
      focus: true
      closePolicy: Popup.NoAutoClose
      contentItem: TextField {
        id: popupInput
        Keys.onEscapePressed: event => {
          root.escapes++;
          event.accepted = true;
        }
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (keys.running)
        return;
      if (root.phase === 0) {
        root.check(root.injector.indexOf("/home/tester/Projects/plugin-settings-host-and-assets/work/") === 0, "task-owned injector required");
        input.forceActiveFocus();
        keys.command = [root.injector, "-s", "200", "--", "/synthetic/export"];
        keys.running = true;
        root.phase = 1;
      } else if (root.phase === 1 && input.text === "/synthetic/export") {
        root.check(root.escapes === 0, "literal slash never becomes Escape");
        input.selectAll();
        keys.command = [root.injector, "-k", "space"];
        keys.running = true;
        root.phase = 2;
      } else if (root.phase === 2 && input.text === " ") {
        keys.command = [root.injector, "-k", "Escape"];
        keys.running = true;
        root.phase = 3;
      } else if (root.phase === 3 && root.escapes === 1) {
        keys.command = [root.injector, "-M", "ctrl", "-k", "a", "-m", "ctrl", "--", "replacement"];
        keys.running = true;
        root.phase = 4;
      } else if (root.phase === 4 && input.text === "replacement") {
        button.forceActiveFocus();
        keys.command = [root.injector, "-k", "space"];
        keys.running = true;
        root.phase = 5;
      } else if (root.phase === 5 && root.clicks === 1) {
        root.check(root.escapes === 1, "named Space never becomes Escape");
        modal.open();
        root.phase = 6;
      } else if (root.phase === 6 && modal.opened) {
        popupInput.forceActiveFocus();
        keys.command = [root.injector, "--", "/Synthetic_Export-17!"];
        keys.running = true;
        root.phase = 7;
      } else if (root.phase === 7 && popupInput.text === "/Synthetic_Export-17!") {
        root.check(root.escapes === 1, "modal printable input never becomes Escape");
        keys.command = [root.injector, "-k", "Escape"];
        keys.running = true;
        root.phase = 8;
      } else if (root.phase === 8 && root.escapes === 2) {
        root.check(modal.visible && popupInput.text === "/Synthetic_Export-17!", "modal text/upper-case/punctuation preserved");
        console.log("PLUGIN_SETTINGS_INPUT: PASS (native and modal fields, literal slash, Shift, Escape, Space, Ctrl+A and native Button)");
        Qt.exit(0);
      }
    }
  }
  Timer {
    interval: 12000
    running: true
    onTriggered: {
      console.error("INPUT_ASSERT: watchdog phase=" + root.phase + " text=" + input.text + " modalText=" + popupInput.text + " escapes=" + root.escapes + " clicks=" + root.clicks);
      Qt.exit(2);
    }
  }
}
