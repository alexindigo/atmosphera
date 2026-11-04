// Real pages/owner/Main controllers; driver isolates their external I/O boundary.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property var cases: []
  property int index: 0
  property var api: null
  property var main: null
  property var held: null
  property var release: null
  property bool started: false
  property bool makeStale: false
  property int baseline: 0
  property string phase: "start"
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  FileView {
    id: inputs
    path: Quickshell.env("I4_EFFECT_INPUTS")
    blockLoading: true
    printErrors: false
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("I4_EFFECT_ASSERT: " + cases[index].manifest.id + " " + phase + " " + label);
  }
  function finish(code) {
    Qt.callLater(function () {
      Qt.exit(code);
    });
  }
  function verifyNext() {
    if (index === cases.length) {
      console.log("I4_PLUGIN_EFFECTS: RESTART_PASS");
      finish(0);
      return;
    }
    var item = cases[index];
    Service.loadPluginSettings(item.manifest.id, function (value) {
      try {
        var consumer = Service.createPluginAPI(item.manifest.id, item.manifest, value, {}, {}, {});
        root.check(consumer.pluginSettings[item.key] === item.staleValue && consumer.pluginSettings.opaque.keep, "restart consumer and unknown data");
        root.index++;
        root.verifyNext();
      } catch (error) {
        console.error(String(error));
        root.finish(2);
      }
    });
  }
  function openNext() {
    if (index === cases.length) {
      console.log("I4_PLUGIN_EFFECTS: SAVED_PASS");
      finish(0);
      return;
    }
    var item = cases[index];
    api = Service.createPluginAPI(item.manifest.id, item.manifest, Object.assign({
                                                                                   opaque: {
                                                                                     keep: true
                                                                                   }
                                                                                 }, item.initial), {}, {}, {});
    var loaded = Object.assign({}, Service.loadedPlugins);
    loaded[item.manifest.id] = {
      api: api
    };
    Service.loadedPlugins = loaded;
    var component = Qt.createComponent("file://" + Registry.getPluginDir(item.manifest.id) + "/Main.qml");
    check(component.status === Component.Ready, "actual Main ready: " + component.errorString());
    main = component.createObject(root, {
                                    pluginApi: api
                                  });
    check(main !== null, "actual Main created");
    api.mainInstance = main;
    var factory = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = factory();
      var wrapper = {
        initialValue: editor.initialValue,
        discard: editor.discard,
        apply: function (value, callback) {
          editor.apply(value, function (result) {
            root.held = result;
            root.release = function () {
              if (result.refreshState === "current")
                wrapper.initialValue = editor.initialValue;
              callback(result);
            };
          });
          if (root.makeStale) {
            var foreign = Object.assign({}, root.api.pluginSettings);
            foreign.opaque = {
              keep: true,
              foreign: true
            };
            root.api.pluginSettings = foreign;
          }
        }
      };
      return wrapper;
    };
    phase = "main-ready";
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    inputs.waitForJob();
    cases = JSON.parse(inputs.text());
    if (verifyOnly)
      verifyNext();
    else
      openNext();
  }
  function deliver() {
    var callback = release;
    release = null;
    held = null;
    callback();
  }
  function consumed(value) {
    var id = cases[index].manifest.id;
    if (main._i4EffectValue !== value)
      return false;
    if (id === "hassio")
      return main.haToken === value;
    if (id === "daily-wallpaper")
      return main.wallpaperTask === null && main._i4HttpUrl.indexOf("mkt=" + String(value).trim().toLowerCase().replace("_", "-")) !== -1 && main._i4DownloadUrl.indexOf("_UHD.jpg") !== -1;
    if (id === "agent-session-status")
      return main.runningCount === 0 && main.agents.length === 0;
    if (id === "port-monitor")
      return main.portCount === (value ? 1 : 2);
    if (id === "github-contributions")
      return main.hasData && main.totalContributions === (value === "i4-retry" ? 9 : 7) && main.username === value;
    return main.enabled === value;
  }
  function fault(mode) {
    action.command = ["python3", Quickshell.env("I4_EFFECT_FAULT"), Quickshell.env("ATMOSPHERA_CONFIG_DIR"), mode];
    action.running = true;
  }
  function drive() {
    if (verifyOnly || phase === "start" || phase === "finished")
      return;
    var item = cases[index];
    var page = popup.settingsPage;
    if (phase === "main-ready") {
      if (item.manifest.id === "port-monitor" && main.portCount !== 2)
        return;
      baseline = main._i4EffectCount;
      popup.openPluginSettings(item.manifest, "settings");
      phase = "cancel";
    } else if (phase === "cancel" && popup.opened && page) {
      check(!popup.dirty, "pristine constructor");
      page[item.field] = item.savedValue;
      page.saveSettings();
      page.saveSettings();
      check(main._i4EffectCount === baseline, "staging has no effect");
      popup.requestClose();
      check(popup.discardPending, "Cancel retains staged input");
      popup.keepEditing();
      popup.requestClose();
      popup.confirmDiscard();
      phase = "cancelled";
    } else if (phase === "cancelled" && !popup.visible && !popup.currentPlugin) {
      check(main._i4EffectCount === baseline, "discard runs no action");
      popup.openPluginSettings(item.manifest, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && page) {
      if (item.manifest.id === "agent-session-status") {
        main.runningCount = 7;
        main.agents = [
              {
                id: "pending"
              }
            ];
      }
      page[item.field] = item.savedValue;
      page.saveSettings();
      page.saveSettings();
      popup.applySettings();
      phase = "saved-held";
    } else if (phase === "saved-held" && release) {
      check(held.status === "saved" && held.refreshState === "current" && main._i4EffectCount === baseline, "held saved has no effect");
      page[item.field] = item.retryValue;
      deliver();
      check(main._i4EffectCount === baseline + 1, "one current action after repeated staging");
      check(page[item.field] === item.retryValue && popup.dirty, "newer local input retained");
      phase = "saved-consumer";
    } else if (phase === "saved-consumer" && consumed(item.savedValue)) {
      page[item.field] = item.savedValue;
      page.saveSettings();
      page.saveSettings();
      popup.applySettings();
      phase = "noop-held";
    } else if (phase === "noop-held" && release) {
      check(held.status === "nothing_to_save" && main._i4EffectCount === baseline + 1, "held no-op");
      deliver();
      phase = "noop-consumer";
    } else if (phase === "noop-consumer" && consumed(item.savedValue)) {
      check(main._i4EffectCount === baseline + 2, "one no-op action");
      phase = "blocking";
      fault("block");
    } else if (phase === "blocked") {
      if (item.manifest.id === "agent-session-status") {
        main.runningCount = 7;
        main.agents = [
              {
                id: "pending"
              }
            ];
      }
      page[item.field] = item.retryValue;
      page.saveSettings();
      page.saveSettings();
      popup.applySettings();
      phase = "failed-held";
    } else if (phase === "failed-held" && release) {
      check(held.status === "failed" && main._i4EffectCount === baseline + 2, "real failure runs no action");
      deliver();
      check(popup.saveFailed && popup.dirty && main._i4EffectCount === baseline + 2, "failure keeps input/action");
      phase = "repairing";
      fault("repair");
    } else if (phase === "retry") {
      popup.applySettings();
      phase = "retry-held";
    } else if (phase === "retry-held" && release) {
      check(held.status === "saved" && held.refreshState === "current" && main._i4EffectCount === baseline + 2, "held Retry");
      deliver();
      phase = "retry-consumer";
    } else if (phase === "retry-consumer" && consumed(item.retryValue)) {
      check(main._i4EffectCount === baseline + 3, "one retained Retry action");
      makeStale = true;
      page[item.field] = item.staleValue;
      page.saveSettings();
      page.saveSettings();
      popup.applySettings();
      phase = "stale-held";
    } else if (phase === "stale-held" && release) {
      check(held.status === "saved" && held.refreshState === "stale", "actual stale completion");
      deliver();
      makeStale = false;
      check(main._i4EffectCount === baseline + 3 && popup.saveFailed, "stale runs no action");
      popup.requestClose();
      popup.confirmDiscard();
      phase = "done";
    } else if (phase === "done" && !popup.visible && !popup.currentPlugin) {
      check(main._i4EffectCount === baseline + 3, "close adds no action");
      console.log("I4_EFFECT_CONSUMER", item.manifest.id, "PASS");
      api.mainInstance = null;
      main.destroy();
      main = null;
      index++;
      openNext();
    }
  }
  Process {
    id: action
    onExited: code => {
      if (code !== 0) {
        console.error("I4_EFFECT_ASSERT: fault helper");
        root.finish(2);
      } else
        root.phase = root.phase === "blocking" ? "blocked" : "retry";
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 860
    implicitHeight: 740
    NPluginSettingsPopup {
      id: popup
      parent: Overlay.overlay
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error));
        root.finish(2);
      }
    }
  }
  Timer {
    interval: 120000
    running: true
    onTriggered: {
      console.error("I4_EFFECT_ASSERT: watchdog", root.phase, root.index);
      root.finish(2);
    }
  }
}
