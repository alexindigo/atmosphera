import QtQuick
import Quickshell
import Quickshell.Io
import qs.Widgets

ShellRoot {
  id: root
  property int stage: 0
  property int failed: 0
  property int hits: 0
  function same(name, actual, expected) {
    const passed = JSON.stringify(actual) === JSON.stringify(expected);
    if (!passed)
      failed++;
    console.log("HIDDEN_KEYS|" + JSON.stringify({
                                                  test: "readiness." + name,
                                                  pass: passed,
                                                  actual: actual,
                                                  expected: expected
                                                }));
  }
  FloatingWindow {
    title: "Key Scope Readiness"
    implicitWidth: 300
    implicitHeight: 150
    Item {
      id: owner
      enabled: false
      Item {
        id: input
        NInputGuard {
          target: input
          focusOnActivation: true
        }
        Keys.onSpacePressed: root.hits++
      }
    }
  }
  Process {
    id: keys
    command: ["python3", "-B", Quickshell.env("LAUNCHER_INPUT_HELPER"), "key", "57:1", "57:0"]
  }
  Timer {
    interval: 350
    running: true
    repeat: true
    onTriggered: {
      if (!input.Window.active)
        return;
      switch (root.stage++) {
      case 0:
        root.same("disabled-ancestor-no-focus", input.activeFocus, false);
        owner.enabled = true;
        break;
      case 1:
        root.same("enabled-ancestor-focus-ready", input.activeFocus, true);
        keys.running = true;
        break;
      case 2:
        root.same("real-key-consumer", root.hits, 1);
        console.log("HIDDEN_KEYS_DONE");
        Qt.exit(root.failed ? 1 : 0);
      }
    }
  }
}
