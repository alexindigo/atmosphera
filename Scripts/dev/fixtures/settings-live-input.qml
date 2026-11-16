import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Modules.Panels.Settings.Bar as Bar

// The actual dialog, page, debounce timer and selected owner. Only receipt
// delivery is held; every held result comes from the real persistence owner.
ShellRoot {
  Loader {
    id: directories
    source: Quickshell.env("LIVE_INPUT_HAS_BOOTSTRAP") === "1" ? "./Commons/SettingsBootstrap.qml" : ""
    readonly property bool ready: source.toString() === "" || (!!item && item.ready)
  }
  Loader {
    active: directories.ready
    sourceComponent: Component {
      Item {
  id: root
  property bool started: false
  property bool ready: false
  property var owner: null
  property var held: []
  property int completed: 0
  property int blurs: 0
  property bool closeWhenIdle: false
  property var receipts: []
  property var commands: []
  function find(item, predicate, seen) {
    seen = seen || [];
    if (!item || seen.indexOf(item) !== -1) return null;
    seen.push(item);
    if (predicate(item)) return item;
    var children = [];
    for (var child of item.children || []) children.push(child);
    for (var resource of item.resources || []) children.push(resource);
    if (item.contentItem) children.push(item.contentItem);
    for (var child of children) {
      var found = find(child, predicate, seen);
      if (found) return found;
    }
    return null;
  }
  function input() {
    return find(dialog.contentItem, function (item) {
      return String(item).indexOf("NTextInput_QMLTYPE") === 0 && item.label === I18n.tr("bar.custom-button.left-click-label");
    });
  }
  function guard() {
    return find(dialog, function (item) { return String(item).indexOf("NSettingsInputGuard_QMLTYPE") === 0; });
  }
  function begin() {
    if (started || !directories.ready || !Settings.isLoaded) return;
    started = true;
    if (Quickshell.env("LIVE_INPUT_COLD") === "1") {
      console.log("LIVE_INPUT_COLD:", JSON.stringify(Settings.data.bar.widgets.left));
      Qt.exit(0);
      return;
    }
    Settings.data.bar.widgets.left = [{id: "CustomButton", leftClickExec: "", opaque: {keep: true}}];
    capture.start();
  }
  Timer {
    id: capture; interval: 20; repeat: true
    onTriggered: {
      root.owner = BarService.createWidgetSettingsEditor("", "left", 0);
      if (!root.owner) return;
      stop();
      dialog.widgetId = "CustomButton";
      dialog.widgetData = root.owner.initialValue;
      dialog.open();
      settle.start();
    }
  }
  Timer {
    id: settle; interval: 100; repeat: true
    onTriggered: {
      if (!root.input() || !root.guard()) return;
      stop();
      root.input().inputItem.editingFinished.connect(function () { root.blurs++; });
      root.ready = true;
    }
  }
  PanelWindow {
    id: window
    implicitWidth: 1100; implicitHeight: 900
    visible: directories.ready
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Item {
      id: scene; anchors.fill: parent
      Bar.BarWidgetSettingsDialog {
        id: dialog
        parent: scene
        screen: Quickshell.screens[0]
        settingsEditor: ({submit: function (fields, callback) {
          root.commands.push(JSON.parse(JSON.stringify(fields)));
          return root.owner.submit(fields, function (result) {
            root.held.push({callback: callback, result: result});
          });
        }})
        onSettingsSaveCompleted: result => {
          root.completed++;
          root.receipts.push(result);
          if (root.closeWhenIdle) Qt.callLater(function () { dialog.saveAndClose(); });
        }
      }
    }
  }
  IpcHandler {
    target: "liveInput"
    function focus(): void { root.input().inputItem.forceActiveFocus(); root.input().inputItem.selectAll(); }
    function release(): void { var next = root.held.shift(); if (next) next.callback(next.result); }
    function close(): void { root.closeWhenIdle = true; if (!dialog.saveBusy) dialog.saveAndClose(); }
    function reopenDetached(): void { root.closeWhenIdle = false; root.owner.detach(); dialog.open(); }
    function discard(): void { dialog.requestDiscard(); if (!dialog.confirmDiscard()) throw new Error("LIVE_INPUT_ASSERT: discard refused"); }
    function clear(): void {
      var control = root.input();
      var button = root.find(control, function (item) { return String(item).indexOf("AtmoIconButton_QMLTYPE") === 0; });
      button.clicked();
    }
    function snapshot(): string {
      var control = root.input(); var guard = root.guard();
      return JSON.stringify({ready: root.ready, focused: !!control && control.inputItem.activeFocus,
        text: control ? control.text : null, busy: dialog.saveBusy, dirty: dialog.settingsDirty,
        guardDirty: guard ? guard.dirty : null, generation: guard ? guard.generation : null,
        held: root.held.length, completed: root.completed, blurs: root.blurs, receipts: root.receipts,
        commands: root.commands, visible: dialog.visible, stored: Settings.data.bar.widgets.left});
    }
    function quit(): void { Qt.exit(0); }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  Connections { target: directories; function onReadyChanged() { root.begin(); } }
  Component.onCompleted: begin()
  Timer { interval: 90000; running: true; onTriggered: { console.error("LIVE_INPUT_ASSERT: watchdog"); Qt.exit(2); } }
      }
    }
  }
}
