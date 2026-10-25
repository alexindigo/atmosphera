import QtQuick
import Quickshell
import Quickshell.Io
import qs.Widgets

ShellRoot {
  id: root
  property int stage: 0
  property var counts: [0, 0, 0, 0, 0, 0, 0, 0]
  property bool reopened: false
  property int failed: 0
  function hit(index) {
    const next = counts.slice();
    next[index]++;
    counts = next;
  }
  function same(name, actual, expected) {
    const passed = JSON.stringify(actual) === JSON.stringify(expected);
    if (!passed)
      failed++;
    console.log("LAUNCHER_SCOPE|" + JSON.stringify({
                                                     test: name,
                                                     pass: passed,
                                                     actual: actual,
                                                     expected: expected
                                                   }));
  }
  FloatingWindow {
    title: "Launcher Shortcut Inactive"
    implicitWidth: 200
    implicitHeight: 100
    Item {
      id: inactiveScope
      anchors.fill: parent
      NScopedShortcut {
        scope: inactiveScope
        sequence: "Return"
        onActivated: root.hit(6)
      }
      NScopedShortcut {
        scope: inactiveScope
        sequence: "Escape"
        onActivated: root.hit(7)
      }
    }
  }
  FloatingWindow {
    title: "Launcher Shortcut Active"
    implicitWidth: 300
    implicitHeight: 120
    Item {
      id: live
      enabled: !root.reopened
      NScopedShortcut {
        scope: live
        sequence: "Return"
        onActivated: root.hit(0)
      }
      NScopedShortcut {
        scope: live
        sequence: "Escape"
        onActivated: root.hit(1)
      }
    }
    Item {
      id: hidden
      visible: root.reopened
      NScopedShortcut {
        scope: hidden
        sequence: "Return"
        onActivated: root.hit(2)
      }
      NScopedShortcut {
        scope: hidden
        sequence: "Escape"
        onActivated: root.hit(3)
      }
    }
    Item {
      id: disabled
      enabled: false
      NScopedShortcut {
        scope: disabled
        sequence: "Return"
        onActivated: root.hit(4)
      }
      NScopedShortcut {
        scope: disabled
        sequence: "Escape"
        onActivated: root.hit(5)
      }
    }
  }
  Process {
    id: focus
    command: ["swaymsg", "[title=\"Launcher Shortcut Active\"]", "focus"]
  }
  Process {
    id: input
  }
  function press(code) {
    input.command = ["python3", "-B", Quickshell.env("LAUNCHER_INPUT_HELPER"), "key", String(code) + ":1", String(code) + ":0"];
    input.running = true;
  }
  Timer {
    running: true
    repeat: true
    interval: 300
    onTriggered: {
      switch (root.stage++) {
      case 0:
        focus.running = true;
        break;
      case 1:
        root.press(28);
        break;
      case 2:
        root.press(1);
        break;
      case 3:
        root.same("active-scope", root.counts.slice(0, 2), [1, 1]);
        root.same("hidden-scope", root.counts.slice(2, 4), [0, 0]);
        root.same("disabled-scope", root.counts.slice(4, 6), [0, 0]);
        root.same("inactive-window", root.counts.slice(6, 8), [0, 0]);
        root.reopened = true;
        break;
      case 4:
        root.press(28);
        break;
      case 5:
        root.press(1);
        break;
      case 6:
        root.same("scope-reopens", root.counts, [1, 1, 1, 1, 0, 0, 0, 0]);
        console.log("LAUNCHER_SCOPE_DONE");
        Qt.exit(root.failed ? 1 : 0);
      }
    }
  }
}
