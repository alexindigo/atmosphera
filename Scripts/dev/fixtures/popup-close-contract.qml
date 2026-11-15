import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.UI
import qs.Widgets

// Actual presentation host and settings popup. The controlled editor holds the
// completion boundary so every close/adoption route sees the same busy state.
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
  property var liveFiles: ["Bar/BarWidgetSettingsDialog.qml", "ControlCenter/ControlCenterWidgetSettingsDialog.qml", "DesktopWidgets/DesktopWidgetSettingsDialog.qml"]
  property var routes: ["close", "native-hide", "dialog", "dynamic", "context", "tray", "bar", "plugin", "desktop"]
  property var editor: ({initialValue: {label: "saved"}, discard: function () { root.discards++; return true; },
    apply: function (value, callback) { root.pending = callback; }})
  property var pageApi: ({staged: false, pluginSettings: {label: "saved"}, busy: false,
    capturePreview: function () { return 0; }, refresh: function () { this.staged = false; },
    complete: function () { root.completions++; }, destroy: function () {}})
  function check(value, label) {
    if (!value) throw new Error("POPUP_CLOSE_ASSERT: " + label);
  }
  function replacement(route) {
    if (route === "close") host.close();
    else if (route === "native-hide") host.visible = false;
    else if (route === "dialog") host.showDialog(candidate);
    else if (route === "dynamic") host.showDynamicContextMenu([], 0, 0, function () {});
    else if (route === "context") PanelService.showContextMenu(menu, anchor, host.shellScreen);
    else if (route === "tray") PanelService.showTrayMenu(host.shellScreen, {}, menu, anchor, 0, 0, "left", 0);
    else if (route === "bar") BarService.openWidgetSettings(host.shellScreen, "left", 0, "Clock", {});
    else if (route === "plugin") BarService.openPluginSettings(host.shellScreen, {id: "not-loaded", entryPoints: {settings: "Page.qml"}});
    else if (route === "desktop") DesktopWidgetRegistry.openWidgetSettings(host.shellScreen, 0, "Clock", {},
      function () { root.cleanupCalls++; }, undefined, undefined, undefined, undefined,
      {initialValue: {id: "Clock"}, detach: function () { root.cleanupCalls++; }});
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    Item { id: anchor; width: 20; height: 20 }
    NPluginSettingsPopup { id: popup; parent: host.dialogParent }
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
      function openAtItem() { visible = true; }
      function showAt() { visible = true; }
      function close() { visible = false; }
    }
  }
  Timer {
    interval: 30; running: true; repeat: true
    onTriggered: {
      try {
        if (root.stage === 0) {
          popup._editor = root.editor;
          popup._pageApi = root.pageApi;
          host.showDialog(popup);
          popup.open();
          root.stage = 1;
        } else if (root.stage === 1 && popup.opened) {
          root.pageApi.staged = true;
          // Reassign the page API to publish the synthetic staged flag.
          popup._pageApi = null; popup._pageApi = root.pageApi;
          root.replacement(root.routes[root.cursor]);
          root.stage = 2;
        } else if (root.stage === 2) {
          console.log("POPUP_CLOSE_OBSERVED " + JSON.stringify({route: root.routes[root.cursor], host: host.visible,
            owns: host.popupContentItem === popup, popup: popup.visible, dirty: popup.dirty, discard: popup.discardPending}));
          root.check(host.visible && host.popupContentItem === popup && popup.visible && BarService.popupOpen,
            "dirty retained through " + root.routes[root.cursor]);
          root.check(popup.discardPending && root.discards === 0 && !menu.visible && !candidate.visible,
            "dirty confirmation without replacement " + root.routes[root.cursor]);
          popup.keepEditing();
          root.pageApi.staged = false;
          popup._submit(false);
          root.check(root.pending !== null && popup.busy, "controlled receipt held");
          root.replacement(root.routes[root.cursor]);
          root.stage = 3;
        } else if (root.stage === 3) {
          root.check(host.visible && host.popupContentItem === popup && popup.visible && popup.busy && !popup.discardPending,
            "busy retained through " + root.routes[root.cursor]);
          root.check(root.discards === 0 && !menu.visible && !candidate.visible, "busy keeps dependencies");
          var callback = root.pending; root.pending = null;
          callback({status: "saved", refreshState: "current"});
          root.check(!popup.busy && !popup.saveFailed && root.completions === root.cursor + 1,
            "held callback delivered after refused close");
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
            root.stage = 5;
          } else root.stage = 0;
        } else if (root.stage === 5) {
          var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/" + root.liveFiles[root.liveIndex]);
          root.check(component.status === Component.Ready, "live dialog component ready");
          root.liveDialog = component.createObject(host.dialogParent, {settingsEditor: {
            submit: function (value, callback) { root.pending = callback; }, detach: function () {}}});
          root.check(root.liveDialog !== null && host.showDialog(root.liveDialog), "live dialog adopted");
          root.liveDialog.open();
          root.liveDialog.queueSettings({label: "held"});
          root.stage = 6;
        } else if (root.stage === 6 && root.pending) {
          root.check(host.close() === false && host.popupContentItem === root.liveDialog && root.liveDialog.saveBusy,
            "live held save refuses host close");
          host.visible = false;
          root.liveTicks = 0;
          root.stage = 7;
        } else if (root.stage === 7 && ++root.liveTicks > 3) {
          root.check(host.visible && root.liveDialog.visible && host.popupContentItem === root.liveDialog && root.liveDialog.saveBusy,
            "live native hide keeps retained submit callback");
          var complete = root.pending; root.pending = null;
          complete({status: "saved"});
          root.check(!root.liveDialog.saveBusy && !root.liveDialog.settingsDirty, "live held submission acknowledged");
          root.check(host.close() === true && !host.visible && !root.liveDialog.visible, "live settled close accepted");
          root.liveDialog.destroy(); root.liveDialog = null;
          root.liveIndex++;
          if (root.liveIndex === root.liveFiles.length) {
            console.log("POPUP_CLOSE_CONTRACT: PASS " + root.cursor + " routes, 3 live dialogs and adoption races");
            Qt.exit(0);
          } else root.stage = 5;
        }
      } catch (error) { console.error(String(error)); Qt.exit(2); }
    }
  }
  Timer { interval: 15000; running: true; onTriggered: { console.error("POPUP_CLOSE_ASSERT: watchdog " + root.stage + "/" + root.cursor); Qt.exit(2); } }
}
