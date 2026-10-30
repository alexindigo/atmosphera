// Inert actual-popup witness. All files and APIs are synthetic, inside VM804.
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property var api: null
  property var instance: null
  property var manifest: ({id: "i4-popup", name: "I4 popup", entryPoints: {settings: "Page.qml"}, metadata: {}})
  property var placement: ({kind: "bar", list: "global", section: "left", index: 0})
  property bool started: false
  property string phase: "start"
  property var held: null
  property var release: null
  property int applies: 0
  property int receipts: 0
  property int ownerSaves: 0
  property bool stale: false
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"

  function check(ok, label) {
    if (!ok)
      throw new Error("I4_PLUGIN_POPUP_ASSERT: " + label);
  }
  function register(value) {
    api = Service.createPluginAPI("i4-popup", manifest, value, {}, {}, {});
    var plugins = Object.assign({}, Service.loadedPlugins);
    plugins["i4-popup"] = {api: api};
    Service.loadedPlugins = plugins;
    var originalFactory = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = originalFactory();
      var wrapper = {
        initialValue: editor.initialValue,
        discard: editor.discard,
        apply: function (value, callback) {
          root.applies++;
          editor.apply(value, function (result) {
            root.held = result;
            root.release = function () {
              if (result.refreshState === "current")
                wrapper.initialValue = editor.initialValue;
              callback(result);
            };
          });
          if (root.stale)
            root.api.pluginSettings = {label: "newer-live", nested: {keep: true}};
        }
      };
      return wrapper;
    };
  }
  function start() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    if (verifyOnly) {
      Service.loadPluginSettings("i4-popup", function (value) {
        try {
          root.register(value);
          root.check(root.api.pluginSettings.label === "shared-final", "restarted shared consumer");
          root.check(PluginInstances.entryFor(root.placement).instanceSettings === undefined, "restarted instance reset");
          root.check(PluginInstances.effectiveSettings(root.api.pluginSettings, root.placement, PluginInstances.revision).label === "shared-final", "restarted instance consumer");
          console.log("I4_PLUGIN_POPUP: RESTART_PASS");
          Qt.exit(0);
        } catch (error) { console.error(String(error)); Qt.exit(2); }
      });
      return;
    }
    register({label: "shared", nested: {keep: true}});
    Settings.data.bar.widgets.left = [{id: "plugin:i4-popup", tag: "keep", instanceSettings: {label: "instance"}}];
    popup.openPluginSettings(manifest, "settings");
    phase = "cancel";
  }
  function deliver() {
    var callback = release;
    release = null;
    held = null;
    callback();
  }
  function drive() {
    var page = popup.settingsPage;
    if (phase === "start" || verifyOnly)
      return;
    if (phase === "cancel" && popup.opened && page) {
      check(!popup.dirty && ownerSaves === 0 && applies === 0, "initialization publishes nothing");
      page.setLabel("cancelled-local");
      popup.requestClose();
      check(popup.discardPending && api.pluginSettings.label === "shared", "local buffer detected without Save");
      popup.keepEditing();
      check(popup.visible && page.labelText === "cancelled-local", "keep editor and buffer");
      popup.confirmDiscard();
      phase = "reopen";
    } else if (phase === "reopen" && !popup.visible && !popup.currentPlugin) {
      check(api.pluginSettings.label === "shared" && ownerSaves === 0, "discard has no settings write");
      popup.openPluginSettings(manifest, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && page) {
      page.setLabel("shared-first");
      popup.applySettings();
      popup.applySettings();
      popup.requestClose();
      popup.confirmDiscard();
      popup.openPluginSettings(manifest, "settings");
      check(applies === 1 && popup.busy && popup.visible && !popup.discardPending && page.saves === 1 && page.completions === 0, "single Apply and busy competition");
      phase = "held";
    } else if (phase === "held" && release) {
      check(receipts === 0 && page.completions === 0 && popup.busy && held.status === "saved", "real IO receipt held before feedback");
      deliver();
      check(!popup.busy && !popup.saveFailed && page.completions === 2 && receipts === 1 && ownerSaves === 1 && !popup.dirty, "receipt-driven page callbacks and current refresh");
      popup.applySettings();
      phase = "noop";
    } else if (phase === "noop" && release) {
      check(held.status === "nothing_to_save" && page.completions === 2, "real ordered no-op receipt");
      deliver();
      check(!popup.saveFailed && page.completions === 4 && applies === 2, "no-op accepted once");
      // Fail at the actual publication destination, not a fabricated result.
      popup.requestClose();
      phase = "failure-open";
    } else if (phase === "failure-open" && !popup.visible && !popup.currentPlugin) {
      // Gate creates this plugin's destination as a directory with a sentinel.
      var original = api;
      api = Service.createPluginAPI("i4-popup-fail", manifest, {label: "failure-base"}, {}, {}, {});
      var plugins = Object.assign({}, Service.loadedPlugins);
      plugins["i4-popup-fail"] = {api: api};
      Service.loadedPlugins = plugins;
      manifest = {id: "i4-popup-fail", name: "failure", entryPoints: {settings: "Page.qml"}, metadata: {}};
      popup.openPluginSettings(manifest, "settings");
      phase = "failure-apply";
    } else if (phase === "failure-apply" && popup.opened && page) {
      page.setLabel("failed-local");
      popup.applySettings();
      phase = "failure-wait";
    } else if (phase === "failure-wait" && !popup.busy) {
      check(popup.saveFailed && popup.dirty && popup.visible && page.labelText === "failed-local" && page.lastStatus === "failed", "IO failure retains editor and has failed callback");
      popup.requestClose();
      check(popup.discardPending, "failed close confirms");
      popup.confirmDiscard();
      phase = "stale-open";
    } else if (phase === "stale-open" && !popup.visible && !popup.currentPlugin) {
      manifest = {id: "i4-popup", name: "stale", entryPoints: {settings: "Page.qml"}, metadata: {}};
      api = Service.getPluginAPI("i4-popup");
      stale = true;
      popup.openPluginSettings(manifest, "settings");
      phase = "stale-apply";
    } else if (phase === "stale-apply" && popup.opened && page) {
      page.setLabel("saved-stale");
      popup.applySettings();
      phase = "stale-wait";
    } else if (phase === "stale-wait" && release) {
      check(held.status === "saved" && held.refreshState === "stale", "actual post-admission stale save");
      deliver();
      check(popup.saveFailed && popup.visible && page.labelText === "saved-stale" && api.pluginSettings.label === "newer-live", "stale refresh keeps local and newer live input");
      popup.requestClose();
      popup.confirmDiscard();
      stale = false;
      phase = "final-open";
    } else if (phase === "final-open" && !popup.visible && !popup.currentPlugin) {
      popup.openPluginSettings(manifest, "settings");
      phase = "final-apply";
    } else if (phase === "final-apply" && popup.opened && page) {
      page.setLabel("shared-final");
      popup.applySettings();
      phase = "final-wait";
    } else if (phase === "final-wait" && release) {
      deliver();
      check(!popup.saveFailed && api.pluginSettings.label === "shared-final", "final shared value");
      popup.requestClose();
      phase = "instance-open";
    } else if (phase === "instance-open" && !popup.visible && !popup.currentPlugin) {
      instance = PluginInstances.apiFor("i4-popup", placement);
      popup.openInstanceSettings(manifest, instance, "settings");
      phase = "instance-apply";
    } else if (phase === "instance-apply" && popup.opened && page) {
      check(page.labelText === "instance", "instance opening consumer");
      page.setLabel("instance-saved");
      popup.applySettings();
      phase = "instance-wait";
    } else if (phase === "instance-wait" && !popup.busy) {
      check(!popup.saveFailed && instance.pluginSettings.label === "instance-saved", "instance applied consumer");
      page.setLabel("discard-on-reset");
      popup.resetButton.clicked();
      check(popup.resetConfirmation.visible, "reset explicit confirmation");
      popup.resetInstanceSettings();
      check(popup.busy && popup.resetConfirmation.visible && page.labelText === "discard-on-reset", "reset awaits receipt before reload");
      phase = "reset-wait";
    } else if (phase === "reset-wait" && !popup.busy) {
      check(!popup.saveFailed && !popup.resetConfirmation.visible && page.labelText === "shared-final", "reset reloads only after current receipt");
      check(PluginInstances.entryFor(placement).instanceSettings === undefined && Settings.data.bar.widgets.left[0].tag === "keep", "reset owning leaf and unknown data");
      popup.requestClose();
      phase = "legacy-open";
    } else if (phase === "legacy-open" && !popup.visible && !popup.currentPlugin) {
      manifest = {id: "i4-popup", name: "legacy", entryPoints: {settings: "Legacy.qml"}, metadata: {}};
      popup.openPluginSettings(manifest, "settings");
      phase = "legacy-close";
    } else if (phase === "legacy-close" && popup.opened && page) {
      popup.requestClose();
      check(popup.discardPending, "untracked legacy buffer conservatively confirms");
      popup.confirmDiscard();
      console.log("I4_PLUGIN_POPUP: SAVED_PASS");
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() { root.start(); }
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) {
      if (pluginId === "i4-popup") root.ownerSaves++;
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 860
    implicitHeight: 740
    NPluginSettingsPopup {
      id: popup
      parent: Overlay.overlay
      onSettingsCompleted: result => { root.receipts++; }
    }
  }
  Component.onCompleted: start()
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try { root.drive(); } catch (error) { console.error(String(error)); Qt.exit(2); }
    }
  }
  Timer {
    interval: 240000
    running: true
    onTriggered: { console.error("I4_PLUGIN_POPUP_ASSERT: watchdog " + root.phase); Qt.exit(2); }
  }
}
