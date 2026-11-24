import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

// Actual host, generic page and native editor. Only a real result's delivery is
// held; no private popup/session state is assigned and no receipt is invented.
ShellRoot {
  id: root
  property var pending: null
  property int discards: 0
  property int completions: 0
  property int cleanupCalls: 0
  property int stage: 0
  property int cursor: 0
  property bool reopenOnClose: false
  property var liveDialog: null
  property int liveIndex: 0
  property int liveTicks: 0
  property int restorationDiscardFence: 0
  property var liveFiles: ["Bar/BarWidgetSettingsDialog.qml", "ControlCenter/ControlCenterWidgetSettingsDialog.qml", "DesktopWidgets/DesktopWidgetSettingsDialog.qml"]
  property var routes: ["close", "native-hide", "dialog", "dynamic", "context", "tray", "bar", "plugin", "desktop"]
  property var editor: null
  property var api: null
  property var manifest: null
  property bool started: false
  readonly property bool cold: Quickshell.env("PHA_CLOSE_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/close-fixture/manifest.json"
    blockLoading: true
    printErrors: false
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    manifestFile.waitForJob();
    manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "close-fixture": manifest
    };
    Service._openSettingsOwner("close-fixture", function (owner) {
      try {
        check(owner !== null, "native close preference owner");
        api = Service.createPluginAPI("close-fixture", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          "close-fixture": {
            api: api
          }
        };
        if (cold) {
          check(api.pluginSettings.label === "held-8", "separate cold native consumer");
          console.log("POPUP_CLOSE_CONTRACT: COLD_PASS");
          Qt.exit(0);
          return;
        }
        var factory = api.createSettingsEditor;
        api.createSettingsEditor = function (fieldIntent) {
          var selected = factory(fieldIntent);
          var wrapped = {
            get ready() {
              return selected.ready;
            },
            get busy() {
              return selected.busy;
            },
            get dirty() {
              return selected.dirty;
            },
            get closed() {
              return selected.closed;
            },
            get error() {
              return selected.error;
            },
            get writable() {
              return selected.writable;
            },
            get fieldCapture() {
              return selected.fieldCapture;
            },
            get handle() {
              return selected.handle;
            },
            get _releasePending() {
              return selected._releasePending;
            },
            get values() {
              return selected.values;
            },
            get previewValues() {
              return selected.previewValues;
            },
            get initialValue() {
              return selected.initialValue;
            },
            fields: selected.fields,
            rebased: selected.rebased,
            whenReady: selected.whenReady,
            previewScope: selected.previewScope,
            copyValue: selected.copyValue,
            release: selected.release,
            discard: function () {
              var accepted = selected.discard();
              if (accepted)
                root.discards++;
              return accepted;
            },
            apply: function (value, callback) {
              selected.apply(value, function (result) {
                root.check(result.status === "saved" && result.refreshState === "current", "real held native receipt");
                root.pending = function () {
                  callback(result);
                };
              });
            }
          };
          root.editor = wrapped;
          return wrapped;
        };
        started = true;
      } catch (error) {
        console.error(String(error) + "\n" + (error.stack || ""));
        Qt.exit(2);
      }
    });
  }
  function check(value, label) {
    if (!value)
      throw new Error("POPUP_CLOSE_ASSERT: " + label);
  }
  function replacement(route) {
    if (route === "close")
      host.close();
    else if (route === "native-hide") {
      host.visible = false;
      // A cancelled pending menu attempt is not a new content presentation.
      host.requestPresentation();
    } else if (route === "dialog")
      host.showDialog(candidate);
    else if (route === "dynamic")
      host.showDynamicContextMenu([], 0, 0, function () {});
    else if (route === "context")
      PanelService.showContextMenu(menu, anchor, host.shellScreen);
    else if (route === "tray")
      PanelService.showTrayMenu(host.shellScreen, {}, menu, anchor, 0, 0, "left", 0);
    else if (route === "bar")
      BarService.openWidgetSettings(host.shellScreen, "left", 0, "Clock", {});
    else if (route === "plugin")
      BarService.openPluginSettings(host.shellScreen, {
                                      id: "not-loaded",
                                      entryPoints: {
                                        settings: "Page.qml"
                                      }
                                    });
    else if (route === "desktop")
      DesktopWidgetRegistry.openWidgetSettings(host.shellScreen, 0, "Clock", {}, function () {
        root.cleanupCalls++;
      }, undefined, undefined, undefined, undefined, {
        initialValue: {
          id: "Clock"
        },
        detach: function () {
          root.cleanupCalls++;
        }
      });
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    Item {
      id: anchor
      width: 20
      height: 20
    }
    NPluginSettingsPopup {
      id: popup
      parent: host.dialogParent
      screen: host.shellScreen
      onSettingsCompleted: root.completions++
    }
    QtObject {
      id: candidate
      property bool visible: false
      function close() {
        visible = false;
        if (root.reopenOnClose)
          host.showContextMenu(menu);
      }
    }
    QtObject {
      id: menu
      property bool visible: false
      property var trayItem: null
      property string widgetSection: ""
      property int widgetIndex: -1
      function openAtItem() {
        visible = true;
      }
      function showAt() {
        visible = true;
      }
      function close() {
        visible = false;
      }
    }
  }
  Timer {
    interval: 30
    running: root.started
    repeat: true
    onTriggered: {
      try {
        if (root.stage === 0) {
          root.check(host.showDialog(popup) && popup.openPluginSettings(root.manifest), "actual generic editor opened");
          root.stage = 1;
        } else if (root.stage === 1 && popup.opened && popup.settingsPage) {
          popup.settingsPage.setLabel("local-" + root.cursor);
          root.replacement(root.routes[root.cursor]);
          root.stage = 2;
        } else if (root.stage === 2) {
          root.check(host.popupContentItem === popup && popup.dirty, "dirty owner retained during host restoration");
          if (root.routes[root.cursor] === "native-hide" && (!host.visible || !popup.visible))
            return;
          console.log("POPUP_CLOSE_OBSERVED " + JSON.stringify({
                                                                 route: root.routes[root.cursor],
                                                                 host: host.visible,
                                                                 owns: host.popupContentItem === popup,
                                                                 popup: popup.visible,
                                                                 dirty: popup.dirty,
                                                                 discard: popup.discardPending
                                                               }));
          root.check(host.visible && host.popupContentItem === popup && popup.visible && BarService.popupOpen, "dirty retained through " + root.routes[root.cursor]);
          root.check(popup.discardPending && root.discards === 0 && !menu.visible && !candidate.visible, "dirty confirmation without replacement " + root.routes[root.cursor]);
          popup.keepEditing();
          popup.settingsPage.setLabel("held-" + root.cursor);
          root.check(popup.applySettings() && popup.busy, "actual Apply admitted");
          root.stage = 11;
        } else if (root.stage === 11 && root.pending) {
          root.replacement(root.routes[root.cursor]);
          root.stage = 3;
        } else if (root.stage === 3) {
          root.check(host.popupContentItem === popup && popup.busy, "busy owner retained during host restoration");
          if (root.routes[root.cursor] === "native-hide" && (!host.visible || !popup.visible))
            return;
          root.check(host.visible && host.popupContentItem === popup && popup.visible && popup.busy && !popup.discardPending, "busy retained through " + root.routes[root.cursor]);
          root.check(root.discards === 0 && !menu.visible && !candidate.visible, "busy keeps dependencies");
          var callback = root.pending;
          root.pending = null;
          callback();
          root.check(!popup.busy && !popup.saveFailed && root.completions === root.cursor + 1, "held callback delivered after refused close");
          popup.confirmDiscard();
          root.stage = 4;
        } else if (root.stage === 4 && !popup.visible) {
          root.check(!host.visible && host.popupContentItem === null && !BarService.popupOpen, "accepted close releases host");
          // onClosed owns the page API; the test does not give it a QObject lifetime.
          root.discards = 0;
          root.cursor++;
          if (root.cursor === root.routes.length) {
            root.check(root.cleanupCalls === 4, "desktop refused-opening cleanup exactly once per attempt");
            var stale = host.requestPresentation();
            var current = host.requestPresentation();
            root.check(host.showDialog(candidate, stale) === false && host.popupContentItem === null, "stale async adoption refused");
            root.check(host.showDialog(candidate, current) === true, "current async adoption accepted");
            root.reopenOnClose = true;
            root.check(host.showDialog(popup) === false && host.popupContentItem === menu, "close callback presentation wins over outer replacement");
            root.reopenOnClose = false;
            host.close();
            root.stage = 8;
          } else
            root.stage = 0;
        } else if (root.stage === 8) {
          root.check(host.showDialog(popup) && popup.openPluginSettings(root.manifest), "restoration-race native editor opened");
          root.stage = 9;
        } else if (root.stage === 9 && popup.opened && popup.settingsPage) {
          popup.settingsPage.setLabel("unapplied-restoration");
          root.check(host.close() === false, "dirty close queues restoration");
          popup.confirmDiscard();
          root.check(host.showDialog(popup) && popup.openPluginSettings(root.manifest), "same QObject adopted for a later native opening");
          root.restorationDiscardFence = root.discards;
          root.stage = 10;
        } else if (root.stage === 10 && popup.opened && popup.settingsPage) {
          root.check(host.popupContentItem === popup && popup._editor === root.editor && root.discards === root.restorationDiscardFence, "obsolete restoration cannot cancel a later opening of the same QObject");
          popup.confirmDiscard();
          root.stage = 5;
        } else if (root.stage === 5) {
          var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/" + root.liveFiles[root.liveIndex]);
          root.check(component.status === Component.Ready, "live dialog component ready");
          root.liveDialog = component.createObject(host.dialogParent, {
                                                     settingsEditor: {
                                                       submit: function (value, callback) {
                                                         root.pending = callback;
                                                       },
                                                       detach: function () {}
                                                     }
                                                   });
          root.check(root.liveDialog !== null && host.showDialog(root.liveDialog), "live dialog adopted");
          root.liveDialog.open();
          root.liveDialog.queueSettings({
                                          label: "held"
                                        });
          root.stage = 6;
        } else if (root.stage === 6 && root.pending) {
          root.check(host.close() === false && host.popupContentItem === root.liveDialog && root.liveDialog.saveBusy, "live held save refuses host close");
          host.visible = false;
          root.liveTicks = 0;
          root.stage = 7;
        } else if (root.stage === 7 && ++root.liveTicks > 3) {
          root.check(host.visible && root.liveDialog.visible && host.popupContentItem === root.liveDialog && root.liveDialog.saveBusy, "live native hide keeps retained submit callback");
          root.liveDialog.requestDiscard();
          root.check(!root.liveDialog.discardPending, "busy live dialog refuses Discard");
          var complete = root.pending;
          root.pending = null;
          complete({
                     status: "saved"
                   });
          root.check(!root.liveDialog.saveBusy && !root.liveDialog.settingsDirty, "live held submission acknowledged");
          root.liveDialog.requestDiscard();
          root.check(!root.liveDialog.discardPending, "clean live dialog has no discarded work");
          root.check(root.liveDialog.queueSettings({
                                                     invalid: Infinity
                                                   }) === false, "actual non-finite input refused by live session");
          root.check(root.liveDialog.saveFailed && !root.liveDialog.settingsDirty, "failed input has no pending admitted fields");
          root.liveDialog.requestDiscard();
          root.check(root.liveDialog.discardPending, "failed-without-dirty input opens Discard confirmation");
          root.liveDialog.keepEditing();
          root.check(!root.liveDialog.discardPending && root.liveDialog.saveFailed && root.liveDialog.visible, "Keep Editing preserves failed input and dialog");
          root.liveDialog.requestDiscard();
          root.check(root.liveDialog.confirmDiscard() && !root.liveDialog.saveFailed, "confirmed Discard clears failed input");
          root.check(!host.visible && !root.liveDialog.visible, "confirmed live discard closes host");
          root.liveDialog.destroy();
          root.liveDialog = null;
          root.liveIndex++;
          if (root.liveIndex === root.liveFiles.length) {
            console.log("POPUP_CLOSE_CONTRACT: PASS " + root.cursor + " routes, 3 live dialogs and adoption races");
            Qt.exit(0);
          } else
            root.stage = 5;
        }
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Timer {
    interval: 90000
    running: true
    onTriggered: {
      console.error("POPUP_CLOSE_ASSERT: watchdog " + root.stage + "/" + root.cursor);
      Qt.exit(2);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
}
