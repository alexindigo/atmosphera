import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Settings.Bar as Bar
import qs.Modules.Panels.Settings.DesktopWidgets as Desktop
import qs.Services.UI
import qs.Widgets

// Actual deferred-text page and actual held-drag page. Only delivery of real
// persistence receipts is held; no preference owner or page writer is replaced.
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
        readonly property bool sliderCase: Quickshell.env("INPUT_COMMIT_CASE") === "slider"
        readonly property bool unsupportedCase: Quickshell.env("INPUT_COMMIT_CASE") === "unsupported"
        readonly property string monitor: Quickshell.screens[0].name
        readonly property var dialog: sliderCase ? barDialog : unsupportedCase ? unsupported : desktopDialog
        property bool started: false
        property bool ready: false
        property var owner: null
        property var held: []
        property var commands: []
        property int releases: 0
        property int blurs: 0
        function find(item, predicate, seen) {
          seen = seen || [];
          if (!item || seen.indexOf(item) !== -1)
            return null;
          seen.push(item);
          if (predicate(item))
            return item;
          var children = [];
          for (var child of item.children || [])
            children.push(child);
          for (var resource of item.resources || [])
            children.push(resource);
          if (item.contentItem)
            children.push(item.contentItem);
          for (var child of children) {
            var found = find(child, predicate, seen);
            if (found)
              return found;
          }
          return null;
        }
        function field(label) {
          if (unsupportedCase)
            return rawInput;
          return find(dialog.contentItem, function (item) {
            return String(item).indexOf("NTextInput_QMLTYPE") === 0 && item.label === label;
          });
        }
        function slider() {
          var wrapper = find(dialog.contentItem, function (item) {
            return String(item).indexOf("NValueSlider_QMLTYPE") === 0 && item.label === I18n.tr("bar.taskbar.icon-scale-label");
          });
          return find(wrapper, function (item) {
            return String(item).indexOf("NSlider_QMLTYPE") === 0;
          });
        }
        function guard() {
          if (unsupportedCase)
            return rawGuard;
          return find(dialog, function (item) {
            return String(item).indexOf("NSettingsInputGuard_QMLTYPE") === 0;
          });
        }
        function stored() {
          return sliderCase ? Settings.data.bar.widgets.left[0] : DesktopWidgetRegistry.getWidgetsForMonitor(monitor)[0];
        }
        function submit(fields, callback) {
          commands.push(JSON.parse(JSON.stringify(fields)));
          return owner.submit(fields, function (result) {
            root.held.push({
                             callback: callback,
                             result: result
                           });
          });
        }
        function begin() {
          if (started || !directories.ready || !Settings.isLoaded)
            return;
          started = true;
          if (Quickshell.env("LIVE_INPUT_COLD") === "1") {
            console.log("INPUT_COMMIT_COLD:", JSON.stringify(stored()));
            Qt.exit(0);
            return;
          }
          if (sliderCase)
            Settings.data.bar.widgets.left = [
                  {
                    id: "Taskbar",
                    iconScale: 0.6,
                    opaque: {
                      keep: true
                    }
                  }
                ];
          else
            Settings.data.desktopWidgets.monitorWidgets = [
                  {
                    name: monitor,
                    widgets: [
                      {
                        id: "AudioVisualizer",
                        width: 320,
                        height: 72,
                        opaque: {
                          keep: true
                        }
                      }
                    ]
                  }
                ];
          capture.start();
        }
        Timer {
          id: capture
          interval: 20
          repeat: true
          onTriggered: {
            root.owner = root.sliderCase ? BarService.createWidgetSettingsEditor("", "left", 0) : DesktopWidgetRegistry.createWidgetSettingsEditor(root.monitor, 0);
            if (!root.owner)
              return;
            stop();
            if (root.unsupportedCase) {
              unsupported.visible = true;
              root.ready = true;
              return;
            }
            root.dialog.widgetId = root.sliderCase ? "Taskbar" : "AudioVisualizer";
            root.dialog.widgetData = root.owner.initialValue;
            root.dialog.open();
            settle.start();
          }
        }
        Timer {
          id: settle
          interval: 50
          repeat: true
          onTriggered: {
            if (!root.guard() || (root.sliderCase ? !root.slider() : !root.field(I18n.tr("common.width"))))
              return;
            stop();
            if (root.sliderCase)
              root.slider().pressedChanged.connect(function () {
                if (!root.slider().pressed)
                  root.releases++;
              });
            else
              root.field(I18n.tr("common.width")).inputItem.editingFinished.connect(function () {
                root.blurs++;
              });
            root.ready = true;
          }
        }
        PanelWindow {
          id: window
          implicitWidth: 1100
          implicitHeight: 900
          visible: directories.ready
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
          Item {
            id: scene
            anchors.fill: parent
            Desktop.DesktopWidgetSettingsDialog {
              id: desktopDialog
              parent: scene
              screen: Quickshell.screens[0]
              settingsEditor: ({
                                 submit: function (fields, callback) {
                                   return root.submit(fields, callback);
                                 }
                               })
            }
            Bar.BarWidgetSettingsDialog {
              id: barDialog
              parent: scene
              screen: Quickshell.screens[0]
              settingsEditor: ({
                                 submit: function (fields, callback) {
                                   return root.submit(fields, callback);
                                 }
                               })
            }
            Item {
              id: unsupported
              anchors.fill: parent
              visible: false
              readonly property bool saveBusy: rawSession.busy
              readonly property bool settingsDirty: rawSession.dirty
              function saveAndClose() {
                rawSession.saveAndClose();
              }
              TextField {
                id: rawInput
                width: 400
                height: 50
                property var inputItem: rawInput
                onEditingFinished: {
                  root.blurs++;
                  rawSession.queue({
                                     width: parseInt(text)
                                   });
                }
              }
              NSettingsInputGuard {
                id: rawGuard
                target: unsupported
                active: unsupported.visible
              }
              NLiveSettingsEditSession {
                id: rawSession
                inputGuard: rawGuard
                editor: ({
                           submit: function (fields, callback) {
                             return root.submit(fields, callback);
                           }
                         })
                onCloseRequested: unsupported.visible = false
              }
            }
          }
        }
        IpcHandler {
          target: "inputCommit"
          function mixed(): void {
            if (root.unsupportedCase) {
              rawInput.forceActiveFocus();
              rawInput.selectAll();
              return;
            }
            var width = root.field(I18n.tr("common.width"));
            width.inputItem.forceActiveFocus();
            width.inputItem.selectAll();
          }
          function queue(): void {
            if (root.unsupportedCase) {
              rawSession.queue({
                                 height: 96
                               });
              return;
            }
            var height = root.field(I18n.tr("common.height"));
            height.text = "96";
            height.inputItem.textEdited();
            height.commitEdit();
          }
          function release(): void {
            var next = root.held.shift();
            if (next)
              next.callback(next.result);
          }
          function close(): void {
            root.dialog.saveAndClose();
          }
          function snapshot(): string {
            var guard = root.guard();
            var control = root.sliderCase ? root.slider() : root.field(I18n.tr("common.width"));
            var point = control ? control.mapToGlobal(control.width / 2, control.height / 2) : ({
                                                                                                  x: 0,
                                                                                                  y: 0
                                                                                                });
            return JSON.stringify({
                                    ready: root.ready,
                                    focused: !!control && (root.sliderCase ? control.activeFocus : control.inputItem.activeFocus),
                                    text: control && !root.sliderCase ? control.text : null,
                                    busy: root.dialog.saveBusy,
                                    dirty: root.dialog.settingsDirty,
                                    guardDirty: guard ? guard.dirty : null,
                                    generation: guard ? guard.generation : null,
                                    pressed: control && root.sliderCase ? control.pressed : false,
                                    value: control && root.sliderCase ? control.value : null,
                                    x: point.x,
                                    y: point.y,
                                    width: control ? control.width : 0,
                                    held: root.held.length,
                                    releases: root.releases,
                                    blurs: root.blurs,
                                    commands: root.commands,
                                    visible: root.dialog.visible,
                                    stored: root.stored()
                                  });
          }
          function quit(): void {
            Qt.exit(0);
          }
        }
        Connections {
          target: Settings
          function onSettingsLoaded() {
            root.begin();
          }
        }
        Connections {
          target: directories
          function onReadyChanged() {
            root.begin();
          }
        }
        Component.onCompleted: begin()
        Timer {
          interval: 90000
          running: true
          onTriggered: {
            console.error("INPUT_COMMIT_ASSERT: watchdog");
            Qt.exit(2);
          }
        }
      }
    }
  }
}
