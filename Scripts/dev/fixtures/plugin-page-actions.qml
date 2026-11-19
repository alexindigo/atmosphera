// Actual pages and preference writer; explicit action collaborators record input.
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
  property var held: null
  property var release: null
  property int calls: 0
  property int closes: 0
  property var consumed: null
  property string phase: "start"
  property bool started: false
  property bool stale: false
  property var actualMain: null
  readonly property var selectedScreen: ({
                                           name: "i4-selected-screen"
                                         })
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  FileView {
    id: inputs
    path: Quickshell.env("I4_ACTION_INPUTS")
    blockLoading: true
    printErrors: false
  }
  QtObject {
    id: collaborator
    property var service: collaborator
    property var batteries: []
    property bool isAvailable: false
    readonly property var state: root.actualMain?.state ?? null
    readonly property bool enabled: root.actualMain?.enabled ?? false
    readonly property var availableFolders: root.actualMain?.availableFolders ?? []
    readonly property string resolvedUrl: root.actualMain?.resolvedUrl ?? ""
    readonly property string apiKeySource: root.actualMain?.apiKeySource ?? "none"
    readonly property bool syncInProgress: root.actualMain?.syncInProgress ?? false
    readonly property bool lastSyncOk: root.actualMain?.lastSyncOk ?? false
    readonly property string lastSyncMessage: root.actualMain?.lastSyncMessage ?? ""
    property int settingsVersion: 0
    onSettingsVersionChanged: {
      root.record();
      if (root.actualMain) root.actualMain.settingsVersion++;
    }
    function refresh() {
      root.record();
      if (root.actualMain) {
        if (root.cases[root.index].plugin === "battery-threshold") root.actualMain.service.refresh();
        else root.actualMain.refresh();
      }
    }
    function refreshNow() {
      root.record();
      if (root.actualMain) root.actualMain.refreshNow();
    }
    function applyColors() {
      root.record();
      if (root.actualMain) root.actualMain.applyColors();
    }
    function startGetNumUpdates() {
      root.record();
      if (root.actualMain) root.actualMain.startGetNumUpdates();
    }
    function restartDaemon() {
      root.record();
      if (root.actualMain) root.actualMain.restartDaemon();
    }
    function setPinnedPanelRequested(value) { root.record(); root.actualMain.setPinnedPanelRequested(value); }
    function setModel(provider, model, persist) { root.record(); root.actualMain.setModel(provider, model, persist); }
    function refreshWallpaperCache(force, toast) { root.record(); root.actualMain.refreshWallpaperCache(force, toast); }
    function hasAnyConfiguredWallpaper() { return root.actualMain.hasAnyConfiguredWallpaper(); }
    function reload() { root.record(); root.actualMain.reload(); }
    function manualSync() { root.record(); root.actualMain.manualSync(); }
    function requestPoll(force) { root.record(); root.actualMain.requestPoll(force); }
    function stateLabel(code) { return root.actualMain.stateLabel(code); }
    function sourceLabel(code) { return root.actualMain.sourceLabel(code); }
    function statusSummary() { return root.actualMain.statusSummary(); }
    function statusColor(code) { return root.actualMain.statusColor(code); }
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("I4_ACTION_ASSERT: " + cases[index].plugin + " " + phase + " " + label);
  }
  function finish(code) {
    Qt.callLater(function () {
      Qt.exit(code);
    });
  }
  function record() {
    calls++;
    consumed = JSON.parse(JSON.stringify(api.pluginSettings));
  }
  function other(value) {
    if (cases[index].retryValue !== undefined) return cases[index].retryValue;
    if (cases[index].plugin === "update-count") return "printf 9";
    return typeof value === "boolean" ? !value : typeof value === "number" ? value + 1 : value === "#ff0000" ? "#00ff00" : value + "-newer";
  }
  function openNext() {
    if (index === cases.length) {
      console.log("I4_PAGE_ACTIONS: SAVED_PASS");
      finish(0);
      return;
    }
    var row = cases[index];
    calls = 0;
    closes = 0;
    consumed = null;
    var seed = {
                                    opaque: {
                                      keep: true
                                    }
                                  };
    seed = Object.assign(seed, row.seed || {});
    if (row.plugin === "air-quality") { seed.useNoctaliaLocation = false; seed.customLongitude = ""; }
    if (row.plugin === "battery-threshold") seed.batteryDevice = "/sys/class/power_supply/BAT0";
    if (row.plugin === "niri-auto-tile") seed.enabled = false;
    if (row.plugin === "hermes-agent") {
      seed.hermesHome = Quickshell.env("ATMOSPHERA_CONFIG_DIR") + "/hermes";
      seed.stateFile = Quickshell.env("ATMOSPHERA_CONFIG_DIR") + "/hermes-state.json";
    }
    if (row.plugin === "linux-wallpaperengine-controller") {
      check(Quickshell.screens.length > 0, "actual wallpaper screen available");
      seed.screens = {};
      for (var screen of Quickshell.screens) seed.screens[screen.name] = {path: "/fixture/wallpaper"};
    }
    api = Service.createPluginAPI(row.plugin, row.manifest, seed, {}, {}, {});
    if (row.plugin !== "weather-indicator") {
      var component = Qt.createComponent("file://" + Registry.getPluginDir(row.plugin) + "/Main.qml");
      check(component.status === Component.Ready, "actual Main ready: " + component.errorString());
      actualMain = component.createObject(root, {pluginApi: api});
      check(actualMain !== null, "actual Main created");
    }
    api.mainInstance = collaborator;
    api.withCurrentScreen = function (callback) {
      callback(row.plugin === "hermes-agent" ? null : root.selectedScreen);
    };
    api.closePanel = function (screen) {
      root.check(screen === root.selectedScreen, "selected screen forwarded");
      root.closes++;
      root.consumed = JSON.parse(JSON.stringify(root.api.pluginSettings));
    };
    var loaded = Object.assign({}, Service.loadedPlugins);
    loaded[row.plugin] = {
      api: api
    };
    Service.loadedPlugins = loaded;
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
          if (root.stale) {
            var newer = Object.assign({}, root.api.pluginSettings);
            newer.foreign = true;
            root.api.pluginSettings = newer;
          }
        }
      };
      return wrapper;
    };
    popup.openPluginSettings(row.manifest, "settings");
    phase = "cancel";
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    inputs.waitForJob();
    cases = JSON.parse(inputs.text()).filter(item => item.action);
    if (verifyOnly)
      verifyNext();
    else
      openNext();
  }
  function verifyNext() {
    if (index === cases.length) {
      console.log("I4_PAGE_ACTIONS: RESTART_PASS");
      finish(0);
      return;
    }
    var row = cases[index];
    Service.loadPluginSettings(row.plugin, function (value) {
      try {
        var reader = Service.createPluginAPI(row.plugin, row.manifest, value, {}, {}, {});
        root.check(reader.pluginSettings[row.key] === row.finalValue && reader.pluginSettings.opaque.keep, "separate restart reads accepted input");
        root.index++;
        root.verifyNext();
      } catch (error) {
        console.error(String(error));
        root.finish(2);
      }
    });
  }
  function stage() {
    if (cases[index].plugin === "hermes-agent")
      popup.settingsPage.applyModel();
    else if (cases[index].plugin === "sticky-notes")
      popup.settingsPage.requestSync();
    else if (cases[index].plugin === "syncthing-status")
      popup.settingsPage.requestRefresh();
    else if (cases[index].plugin === "niri-auto-tile")
      popup.settingsPage.saveSettings(true);
    else
      popup.settingsPage.saveSettings();
  }
  function deliver() {
    var callback = release;
    release = null;
    held = null;
    callback();
  }
  function expectedCalls(step) {
    return cases[index].action === "closePanel" ? 0 : step * (cases[index].actionCount || 1);
  }
  function expectedCloses(step) {
    return ["weather-indicator", "update-count"].indexOf(cases[index].plugin) >= 0 ? step : 0;
  }

  function settled(value) {
    var name = cases[index].plugin;
    if (name === "arch-updater") return !actualMain.refreshing && actualMain.updates.length === 1 && actualMain.updates[0].name === (value === cases[index].retryValue ? "retryPkg" : "currentPkg");
    if (name === "hermes-agent") return actualMain.state.summary.model.name === String(value).trim() && actualMain.state.summary.model.provider === "fixture-provider" && actualMain.pinnedPanelRequested === api.pluginSettings.panelPinned;
    if (name === "linux-wallpaperengine-controller") return actualMain.defaultFps === value && actualMain.cachedWallpaperItems.length === 0 && !actualMain.wallpapersFolderAccessible;
    if (name === "sticky-notes") return actualMain.lastSyncOk && actualMain.lastSyncMessage === "fixture:" + value && !actualMain.syncInProgress;
    if (name === "syncthing-status") return !actualMain.busy && actualMain.resolvedUrl === value && actualMain.configuredDevices === 2 && actualMain.monitoredFolders === 1;
    if (name === "air-quality") return actualMain.cfg.customLatitude === value && !actualMain.loading && actualMain.errorMessage === "";
    if (name === "amd-gpu-monitor") return actualMain.available && actualMain.deviceIndex === value && actualMain.gpuUse === value * 10 + 7;
    if (name === "battery-threshold") return actualMain.service.thresholdFile === value + "/charge_control_end_threshold";
    if (name === "ds4-colors") {
      var color = Qt.color(value);
      return actualMain.currentR === Math.round(color.r * 255) && actualMain.currentG === Math.round(color.g * 255) && actualMain.currentB === Math.round(color.b * 255);
    }
    if (name === "pomodoro") return actualMain.workDuration === value * 60;
    if (name === "niri-auto-tile") return actualMain.pendingRestart && actualMain.perWorkspace === value && (actualMain.daemonProcess.command.indexOf("--per-workspace") >= 0) === value;
    if (name === "update-count") return actualMain.updateCount === (value === "printf 9" ? 9 : 7);
    return closes > 0 && consumed[cases[index].key] === value;
  }
  function fault(mode) {
    action.command = ["python3", Quickshell.env("I4_ACTION_FAULT"), Quickshell.env("ATMOSPHERA_CONFIG_DIR"), mode];
    action.running = true;
  }
  function drive() {
    if (verifyOnly || phase === "start")
      return;
    var row = cases[index], page = popup.settingsPage;
    if (phase === "cancel" && popup.opened && page) {
      check(!popup.dirty && calls === 0 && closes === 0, "constructor has no action or input");
      page[row.field] = row.finalValue;
      stage();
      stage();
      check(calls === 0 && closes === 0, "repeated staging has no action");
      popup.requestClose();
      check(popup.discardPending, "Cancel asks");
      popup.confirmDiscard();
      phase = "cancelled";
    } else if (phase === "cancelled" && !popup.visible && !popup.currentPlugin) {
      check(calls === 0 && closes === 0, "Cancel has no action");
      popup.openPluginSettings(row.manifest, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && page) {
      page[row.field] = row.finalValue;
      stage();
      stage();
      popup.applySettings();
      phase = "saved";
    } else if (phase === "saved" && release) {
      check(held.status === "saved" && calls === 0 && closes === 0, "held receipt has no action");
      page[row.field] = other(row.finalValue);
      deliver();
      check(calls === expectedCalls(1) && closes === expectedCloses(1), "coalesced current completion");
      check(consumed[row.key] === row.finalValue && page[row.field] === other(row.finalValue) && popup.dirty, "action sees accepted owner; newer local input retained");
      phase = "saved-consumer";
    } else if (phase === "saved-consumer" && settled(row.finalValue)) {
      page[row.field] = row.finalValue; stage(); stage(); popup.applySettings(); phase = "noop";
    } else if (phase === "noop" && release) {
      check(held.status === "nothing_to_save", "real no-op receipt");
      deliver();
      var step = row.plugin === "air-quality" ? 1 : 2;
      check(calls === expectedCalls(step) && closes === expectedCloses(2), "existing conditional/no-op action policy");
      phase = "noop-consumer";
    } else if (phase === "noop-consumer" && settled(row.finalValue)) {
      phase = "blocking"; fault("block");
    } else if (phase === "blocked") {
      page[row.field] = other(row.finalValue);
      stage();
      stage();
      popup.applySettings();
      phase = "failed";
    } else if (phase === "failed" && release) {
      check(held.status === "failed", "real writer failure");
      var before = calls, beforeClose = closes;
      deliver();
      check(calls === before && closes === beforeClose && popup.saveFailed && popup.dirty, "failure retains action/input");
      phase = "repairing";
      fault("repair");
    } else if (phase === "retry") {
      popup.applySettings();
      phase = "retried";
    } else if (phase === "retried" && release) {
      check(held.status === "saved" && held.refreshState === "current", "real repaired Retry");
      var before = calls, beforeClose = closes;
      deliver();
      check(calls === before + expectedCalls(1) && closes === beforeClose + expectedCloses(1) && consumed[row.key] === other(row.finalValue), "one retained action sees Retry input");
      phase = "retry-consumer";
    } else if (phase === "retry-consumer" && settled(other(row.finalValue))) {
      stale = true; page[row.field] = row.finalValue; stage(); stage(); popup.applySettings(); phase = "stale";
    } else if (phase === "stale" && release) {
      check(held.status === "saved" && held.refreshState === "stale", "real stale completion");
      var before = calls, beforeClose = closes;
      deliver();
      stale = false;
      check(calls === before && closes === beforeClose && popup.saveFailed, "stale action refused");
      popup.requestClose();
      popup.confirmDiscard();
      phase = "done";
    } else if (phase === "done" && !popup.visible && !popup.currentPlugin) {
      console.log("I4_PAGE_ACTION", row.plugin, "PASS");
      api.mainInstance = null;
      if (actualMain) { actualMain.destroy(); actualMain = null; }
      index++;
      openNext();
    }
  }
  Process {
    id: action
    onExited: code => {
      if (code !== 0) {
        console.error("I4_ACTION_ASSERT: fault helper");
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
    interval: 90000
    running: true
    onTriggered: {
      console.error("I4_ACTION_ASSERT: watchdog", root.phase, root.index);
      root.finish(2);
    }
  }
}
