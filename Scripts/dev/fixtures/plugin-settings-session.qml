// Actual popup, native editors and real persistence. Session extraction only;
// this does not certify the later field-only page role or Todo host correction.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property bool started: false
  property var api: null
  property var instance: null
  property var held: null
  property var afterFault: null
  property bool faultBlocked: false
  property bool hold: false
  property bool stale: false
  property int applies: 0
  property int receipts: 0
  property string phase: "opening"
  property var manifest: null
  readonly property var placement: ({kind: "bar", list: "global", section: "left", index: 0})
  readonly property bool cold: Quickshell.env("PHA_SESSION_COLD") === "1"
  FileView { id: manifestFile; path: Settings.configDir + "plugins/session-fixture/manifest.json"; blockLoading: true; printErrors: false }
  function check(ok, message) { if (!ok) throw new Error("SESSION_ASSERT: " + message); }
  function fail(error) { console.error(String(error) + "\n" + (error.stack || "")); Qt.exit(2); }
  function show(selected) {
    if (host.popupContentItem !== popup) check(host.showDialog(popup), "actual host admitted");
    check(selected ? popup.openInstanceSettings(manifest, selected) : popup.openPluginSettings(manifest), "selected editor open admitted");
  }
  function fault(mode, next) {
    afterFault = next;
    faultProcess.command = ["python3", "-B", Quickshell.env("PHA_SESSION_FAULT"), Settings.configDir.replace(/\/$/, ""), mode];
    faultProcess.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    manifestFile.waitForJob();
    manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {"session-fixture": manifest};
    Service._openSettingsOwner("session-fixture", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("session-fixture", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {"session-fixture": {api: api}};
        if (cold) {
          check(api.pluginSettings.label === "final", "separate cold shared consumer");
          PluginInstances.openRuntime(api, placement, function (result) {
            try {
              check(result.status === "opened" && result.editor.values.label === "final", "separate cold instance consumer");
              check(PluginInstances.entryFor(placement).instanceSettings === undefined, "cold reset removed override");
              result.editor.detach();
              console.log("PLUGIN_SETTINGS_SESSION: COLD_PASS"); Qt.exit(0);
            } catch (error) { fail(error); }
          });
          return;
        }
        var factory = api.createSettingsEditor;
        api.createSettingsEditor = function () {
          var editor = factory();
          return {
            get initialValue() { return editor.initialValue; }, get values() { return editor.values; },
            get previewValues() { return editor.previewValues; }, get writable() { return editor.writable; },
            get ready() { return editor.ready; }, get busy() { return editor.busy; }, get dirty() { return editor.dirty; },
            get closed() { return editor.closed; }, get error() { return editor.error; },
            whenReady: editor.whenReady, release: editor.release, discard: editor.discard,
            copyValue: editor.copyValue, previewScope: editor.previewScope, rebased: editor.rebased, fields: editor.fields,
            apply: function (value, callback) {
              applies++;
              editor.apply(value, function (result) {
                if (root.hold) root.held = function () { callback(result); };
                else callback(result);
              });
              if (root.stale) root.api.pluginSettings.label = "newer";
            }
          };
        };
        Settings.data.bar.widgets.left = [{id: "plugin:session-fixture", tag: "keep", instanceSettings: {label: "instance"}}];
        Settings.saveSelected([["bar", "widgets", "left"]], function (result) {
          try { check(result.status !== "failed", "fixture placement saved"); show(); phase = "cancel"; }
          catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function drive() {
    var page = popup.settingsPage;
    if (phase === "cancel" && popup.opened && page) {
      check(!popup.dirty && api.pluginSettings.label === "shared", "untouched opening is nonpublishing");
      page.setLabel("local-discard");
      check(host.close() === false && popup.discardPending, "dirty host Close refused");
      popup.keepEditing();
      check(popup.settingsPage === page && page.labelText === "local-discard", "Keep editing retains exact page/input");
      check(!popup.openPluginSettings(manifest), "second Open refuses replacement");
      popup.confirmDiscard(); phase = "reopen";
    } else if (phase === "reopen" && !popup.visible && !popup.currentPlugin) {
      check(api.pluginSettings.label === "shared", "discard left owner unchanged"); show(); phase = "apply";
    } else if (phase === "apply" && popup.opened && page) {
      page.setLabel("saved"); hold = true;
      popup.applySettings(); popup.applySettings();
      check(!popup.requestClose() && !popup.confirmDiscard() && popup.busy && applies === 1, "busy excludes competing actions");
      phase = "held";
    } else if (phase === "held" && held) {
      check(popup.busy && receipts === 0 && page.callbacks === 0, "native result held before completion feedback");
      var complete = held; held = null; hold = false; complete();
      check(!popup.busy && !popup.saveFailed && !popup.dirty && page.callbacks === 2 && page.completionOrder === "signal,callback,callback", "current receipt and signal-before-callback ordering");
      page.submitInput = false;
      popup.applySettings(); phase = "noop";
    } else if (phase === "noop" && !popup.busy) {
      check(!popup.saveFailed && page.lastStatus === "nothing_to_save" && page.callbacks === 4, "actual no-op receipt acknowledged");
      page.submitInput = true;
      fault("block", function () { popup.settingsPage.setLabel("failed-local"); popup.applySettings(); phase = "failure"; });
      phase = "fault";
    } else if (phase === "failure" && !popup.busy) {
      check(popup.saveFailed && popup.visible && page.labelText === "failed-local" && page.lastStatus === "failed", "real IO failure retains input");
      check(!popup.requestClose() && popup.discardPending, "failed close requires discard");
      popup.keepEditing();
      fault("repair", function () { popup.applySettings(); phase = "retry"; }); phase = "fault";
    } else if (phase === "retry" && !popup.busy) {
      check(!popup.saveFailed && page.lastStatus !== "failed", "same editor retry succeeds after repair");
      stale = true; page.setLabel("stale-local"); popup.applySettings(); phase = "stale";
    } else if (phase === "stale" && !popup.busy) {
      check(popup.saveFailed && page.labelText === "stale-local" && api.pluginSettings.label === "newer", "saved-but-stale retains local input and newer owner");
      popup.requestClose(); popup.confirmDiscard(); stale = false; phase = "final-open";
    } else if (phase === "final-open" && !popup.visible && !popup.currentPlugin) {
      show(); phase = "final";
    } else if (phase === "final" && popup.opened && page) {
      page.setLabel("final"); popup.applySettings(); phase = "final-wait";
    } else if (phase === "final-wait" && !popup.busy) {
      check(!popup.saveFailed && api.pluginSettings.label === "final", "current final shared value");
      popup.requestClose(); phase = "instance-open";
    } else if (phase === "instance-open" && !popup.visible && !popup.currentPlugin) {
      instance = PluginInstances.apiFor("session-fixture", placement); show(instance); phase = "instance";
    } else if (phase === "instance" && popup.opened && page) {
      check(page.labelText === "instance", "selected instance values");
      page.setLabel("selected"); popup.applySettings(); phase = "instance-wait";
    } else if (phase === "instance-wait" && !popup.busy && instance.pluginSettings.label === "selected") {
      check(!popup.saveFailed && api.pluginSettings.label === "final", "instance Apply does not change shared owner");
      page.setLabel("unsaved-before-reset"); popup.resetButton.clicked(); popup.resetInstanceSettings(); phase = "reset";
    } else if (phase === "reset" && !popup.busy && popup.settingsPage && popup.settingsPage.labelText === "final") {
      check(!popup.saveFailed && !popup.dirty && !popup.resetConfirmation.visible, "current Reset reloads and retires input");
      check(PluginInstances.entryFor(placement).instanceSettings === undefined && Settings.data.bar.widgets.left[0].tag === "keep", "native reset sparse persistence and opaque row retained");
      check(popup.requestClose(), "clean Close accepted");
      console.log("PLUGIN_SETTINGS_SESSION: PASS"); Qt.exit(0);
    }
  }
  Process {
    id: faultProcess
    onExited: code => {
      try {
        check(code === 0, "guarded permission fault");
        faultBlocked = command[command.length - 1] === "block";
        var next = afterFault; afterFault = null; next();
      } catch (error) { fail(error); }
    }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    NPluginSettingsPopup { id: popup; parent: host.dialogParent; screen: Quickshell.screens[0]; onSettingsCompleted: root.receipts++ }
  }
  Timer { interval: 50; running: true; repeat: true; onTriggered: { try { root.drive(); } catch (error) { root.fail(error); } } }
  Timer { interval: 45000; running: true; onTriggered: root.fail("session watchdog at " + root.phase); }
  Component.onCompleted: begin()
}
