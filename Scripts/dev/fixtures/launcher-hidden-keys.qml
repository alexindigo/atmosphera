import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.FileChooser

ShellRoot {
  id: root
  readonly property string kind: Quickshell.env("LAUNCHER_KEY_CASE")
  property int stage: 0
  property int hits: 0
  property int failed: 0
  property bool callerEnabled: true
  property bool otherVisible: false
  function same(name, actual, expected) {
    const passed = JSON.stringify(actual) === JSON.stringify(expected);
    if (!passed)
      failed++;
    console.log("HIDDEN_KEYS|" + JSON.stringify({
                                                  test: kind + "." + name,
                                                  pass: passed,
                                                  actual: actual,
                                                  expected: expected
                                                }));
  }
  QtObject {
    id: previewData
    property var item: null
    property string path: ""
    property string status: "ready"
    property string kind: "unknown"
    property string errorText: ""
  }
  FloatingWindow {
    title: "Launcher Hidden Keys Regression"
    implicitWidth: 700
    implicitHeight: 500
    Item {
      id: focusOwner
      anchors.fill: parent
    }
    Loader {
      id: subject
      anchors.fill: parent
      sourceComponent: root.kind === "header" ? header : root.kind === "overlay" ? overlay : generic
    }
  }
  FloatingWindow {
    visible: root.otherVisible
    title: "Other Key Surface"
    implicitWidth: 200
    implicitHeight: 100
  }
  Component {
    id: generic
    Item {
      enabled: root.callerEnabled
      Keys.onSpacePressed: root.hits++
      Loader {
        Component.onCompleted: {
          if (Quickshell.env("LAUNCHER_GUARD_AVAILABLE") === "1")
            setSource(Qt.resolvedUrl("Widgets/NInputGuard.qml"), {
                        target: parent
                      });
        }
      }
    }
  }
  Component {
    id: header
    FileColumnHeader {
      enabled: root.callerEnabled
      text: "Actual chooser column header"
      onClicked: root.hits++
    }
  }
  Component {
    id: overlay
    FileQuickLook {
      enabled: root.callerEnabled
      preview: previewData
      opened: true
      onCloseRequested: root.hits++
      Component.onCompleted: {
        if (this.keyFocusOwner !== undefined)
          this.keyFocusOwner = focusOwner;
      }
    }
  }
  Process {
    id: focus
    command: ["swaymsg", "[title=\"Launcher Hidden Keys Regression\"]", "focus"]
  }
  Process {
    id: input
  }
  function press() {
    const code = kind === "header" ? "28" : "57";
    input.command = ["python3", "-B", Quickshell.env("LAUNCHER_INPUT_HELPER"), "key", code + ":1", code + ":0"];
    input.running = true;
  }
  function show(value) {
    if (kind === "overlay")
      subject.item.opened = value;
    else
      subject.item.visible = value;
  }
  Timer {
    running: true
    repeat: true
    interval: 250
    onTriggered: {
      switch (root.stage++) {
      case 0:
        focus.running = true;
        break;
      case 1:
        subject.item.forceActiveFocus();
        break;
      case 2:
        root.press();
        break;
      case 3:
        root.same("visible-control", root.hits, 1);
        root.show(false);
        break;
      case 4:
        root.same("hidden-disabled", subject.item.enabled, false);
        root.same("hidden-drops-focus", subject.item.activeFocus, false);
        if (root.kind === "overlay")
          root.same("focus-returns-to-owner", focusOwner.activeFocus, true);
        root.press();
        break;
      case 5:
        root.same("hidden-no-action", root.hits, 1);
        root.callerEnabled = false;
        root.show(true);
        break;
      case 6:
        root.same("caller-disabled-restored", subject.item.enabled, false);
        root.press();
        break;
      case 7:
        root.same("disabled-no-action", root.hits, 1);
        root.callerEnabled = true;
        break;
      case 8:
        root.same("caller-binding-restored", subject.item.enabled, true);
        subject.item.forceActiveFocus();
        break;
      case 9:
        root.press();
        break;
      case 10:
        root.same("reopened-control", root.hits, 2);
        root.otherVisible = true;
        break;
      case 11:
        root.same("inactive-disabled", subject.item.enabled, false);
        root.same("inactive-drops-focus", subject.item.activeFocus, false);
        root.press();
        break;
      case 12:
        root.same("inactive-no-action", root.hits, 2);
        root.otherVisible = false;
        focus.running = true;
        break;
      case 13:
        root.same("reactivated-enabled", subject.item.enabled, true);
        root.same("reactivated-focus", subject.item.activeFocus, true);
        root.press();
        break;
      case 14:
        root.same("reactivated-control", root.hits, 3);
        console.log("HIDDEN_KEYS_DONE");
        Qt.exit(root.failed ? 1 : 0);
      }
    }
  }
}
