// Real released desktop fallback and native plugin owners, with inert process
// endpoints. No production source is instrumented or replaced.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings.DesktopWidgets
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string finding: Quickshell.env("PHA_FINDING")
  readonly property string pluginKey: Quickshell.env("PHA_PLUGIN")
  readonly property var placement: ({kind: "desktop", screenName: Quickshell.screens[0].name, index: 0})
  property string phase: "opening"
  property bool started: false
  property var api: null
  property var instanceApi: null
  property var main: null
  property var desktop: null
  property var panel: null
  property var editedInput: null
  property var page: null
  property int saves: 0
  property int ticks: 0
  property bool manualConfirmed: false

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/" + root.pluginKey + "/manifest.json"
    blockLoading: true
    printErrors: false
  }

  function check(condition, message) {
    if (!condition) throw new Error(finding + "_RED_ASSERT: " + message);
  }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function find(item, predicate) {
    if (!item) return null;
    if (predicate(item)) return item;
    for (var child of item.children || []) {
      var result = find(child, predicate);
      if (result) return result;
    }
    return null;
  }
  function construct(entry, parent, selected, context) {
    var url = "file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry];
    var component = Qt.createComponent(url);
    check(component.status === Component.Ready, entry + " compiles: " + component.errorString());
    var item = PluginLoader.createObject(pluginKey, entry, component, parent, selected, context);
    check(item !== null, entry + " constructed through production loader");
    return item;
  }
  function baselineReady() {
    if (pluginKey === "git-companion") return !main.loading && main.issuesList.length === 1;
    if (pluginKey === "arch-updater") return !main.refreshing && main.updates.length === 1;
    return !main.loading && main.hasData;
  }
  function assertOldConsumer() {
    if (pluginKey === "air-quality")
      check(main.usAqi === 17 && desktop.hasData && desktop.aqi === 17, "old location AQI still presented");
    else if (pluginKey === "github-contributions")
      check(main.totalContributions === 7 && desktop.hasData && desktop.allDays[0].count === 7,
            "old account graph still presented");
    else if (pluginKey === "arch-updater") {
      check(main.updates[0].name === "synthetic-old", "old command result still presented");
      check(find(desktop, function (item) { return item.text === "synthetic-old"; }) !== null,
            "actual desktop list still renders old package");
    }
  }
  function mark() {
    console.log("RED_CONTROL " + finding + ": REPRODUCED (actual Main/" + (finding === "P048" ? "Panel" : "desktop") + ", native save, controlled endpoints)");
    Qt.exit(0);
  }
  function begin() {
    if (started || !Settings.isLoaded) return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    var registered = {}; registered[pluginKey] = manifest;
    Registry.installedPlugins = registered;
    Service._openSettingsOwner(pluginKey, function (owner) {
      try {
        check(owner !== null, "native owner opened");
        api = Service.createPluginAPI(pluginKey, manifest, owner, {}, {}, {});
        var loaded = {}; loaded[pluginKey] = {api: api}; Service.loadedPlugins = loaded;
        main = construct("main", root, api, {});
        api.mainInstance = main;
        Settings.data.desktopWidgets.monitorWidgets = [{name: placement.screenName, widgets: [{id: "plugin:" + pluginKey}]}];
        Settings.saveSelected([["desktopWidgets", "monitorWidgets"]], function (receipt) {
          try {
            check(receipt.status !== "failed", "placement persisted");
            instanceApi = PluginInstances.apiFor(pluginKey, placement);
            check(instanceApi !== null, "selected placement API");
            phase = "baseline";
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function drive() {
    if (phase === "baseline" && instanceApi.settingsReady && baselineReady()) {
      desktop = construct("desktopWidget", host.contentItem, instanceApi,
                          {screen: Quickshell.screens[0], widgetData: {id: "plugin:" + pluginKey}, widgetIndex: 0});
      check(host.showDialog(dialog), "actual popup presentation admitted");
      dialog.open();
      phase = "page";
    } else if (phase === "page" && dialog.opened) {
      page = find(dialog.contentItem, function (item) {
        return item.pluginApi === root.api && typeof item.saveSettings === "function";
      });
      check(page !== null, "actual generic page received the live shared API");
      saves = 0;
      if (finding === "P048") {
        var input = find(page, function (item) { return item.label === api.tr("settings.repo.label") && typeof item.commitEdit === "function"; });
        check(input !== null, "real repository input");
        // Native selection is fixture setup, not a page/state assignment.
        // Wait until the popup's own deferred focus setup has run before
        // delivering real text keys; virtual Ctrl+A can race initial focus.
        editedInput = input.inputItem;
        phase = "focus-input";
        return;
      }
      if (pluginKey === "air-quality") {
        var latitude = find(page, function (item) { return item.label === api.tr("settings.customLatitude") && typeof item.commitEdit === "function"; });
        check(latitude !== null, "real latitude input");
        latitude.text = finding === "P161" ? "" : "3";
      } else if (pluginKey === "github-contributions") {
        var account = find(page, function (item) { return item.label === api.tr("settings.username.label") && typeof item.commitEdit === "function"; });
        check(account !== null, "real account input");
        account.text = finding === "P143" ? "" : "synthetic-beta";
      } else if (pluginKey === "arch-updater") {
        var command = find(page, function (item) { return item.label === api.tr("settings.general.systemCmd.text") && typeof item.commitEdit === "function"; });
        check(command !== null, "real read-command input");
        command.text = Quickshell.env("PHA_ENDPOINT") + " system-new";
      }
      dialog.saveAndClose();
      phase = "saved";
      ticks = 0;
    } else if (phase === "focus-input") {
      editedInput.forceActiveFocus();
      editedInput.selectAll();
      check(editedInput.activeFocus && editedInput.selectionStart === 0 && editedInput.selectionEnd === editedInput.text.length,
            "native repository selection is ready before typing");
      typing.command = ["wtype", "--", "synthetic/beta"];
      typing.running = true;
      phase = "typed";
    } else if (phase === "typed" && !typing.running && saves > 0 && main.repo === "synthetic/beta" && !main.loading
               && main.issuesList[0]?.title === "result for synthetic/beta") {
      check(dialog.visible, "per-interaction shared save occurred before Close or Apply");
      check(api.pluginSettings.repo === "synthetic/beta", "shared native owner changed");
      if (!panel) panel = construct("panel", host.contentItem, instanceApi, {});
      if (!find(panel, function (item) { return item.text === "result for synthetic/beta"; })) return;
      // Discarding the unrelated placement live-field editor cannot undo it.
      check(dialog.requestClose() === true, "actual fallback Close accepted");
      mark();
    } else if (phase === "saved" && saves > 0 && ++ticks >= 15) {
      check(!("settingsCompleted" in api), "old live API has no page completion signal");
      assertOldConsumer();
      if (finding === "P143" || finding === "P161") {
        // Even an explicit runtime refresh cannot clear old-source presentation.
        main.refresh();
        phase = "invalid";
        ticks = 0;
      } else {
        // Positive endpoint control: the same real consumer does fetch the new
        // config when explicitly refreshed, proving the old host skipped it.
        main.refresh();
        phase = "manual";
      }
    } else if (phase === "invalid" && ++ticks >= 5) {
      assertOldConsumer();
      if (finding === "P143")
        check(main.username === "" && desktop.footerText() === "@", "old graph belongs to now-empty account");
      else
        check(api.pluginSettings.customLatitude === "" && main.errorMessage === "", "invalid location returns without a state error");
      mark();
    } else if (phase === "manual" && baselineReady()) {
      var changed = pluginKey === "air-quality" ? main.usAqi === 151 && desktop.aqi === 151
                  : pluginKey === "github-contributions" ? main.totalContributions === 29 && desktop.allDays[0]?.count === 29
                  : main.updates[0]?.name === "synthetic-new";
      if (changed) { manualConfirmed = true; mark(); }
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() { root.begin(); }
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(pluginId, result) {
      if (pluginId === root.pluginKey && result.status !== "failed") root.saves++;
    }
  }
  Process {
    id: typing
    onExited: exitCode => { if (exitCode !== 0) root.fail("Wayland input endpoint failed: " + exitCode); }
  }
  PopupMenuWindow {
    id: host
    shellScreen: Quickshell.screens[0]
    // Input isolation for the disposable fixture only, not production chrome.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    DesktopWidgetSettingsDialog {
      id: dialog
      parent: host.dialogParent
      widgetId: "plugin:" + root.pluginKey
      widgetIndex: 0
      widgetData: ({id: "plugin:" + root.pluginKey})
      screen: Quickshell.screens[0]
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: { try { root.drive(); } catch (error) { root.fail(error); } }
  }
  Timer { interval: 45000; running: true; onTriggered: root.fail("watchdog at " + root.phase); }
  Component.onCompleted: begin()
}
