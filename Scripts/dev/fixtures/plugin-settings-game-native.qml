import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_GAME_SCOPE")
  readonly property string mode: Quickshell.env("PHA_GAME_MODE")
  readonly property string boundary: Quickshell.env("PHA_GAME_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_GAME_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_GAME_RED") === "1"
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var main: null
  property var bar: null
  property var panel: null
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/tamagotchi/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/tamagotchi/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete game documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1200
    implicitHeight: 950
    Item {
      id: content
      width: 1200
      height: 950
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("GAME_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("tamagotchi", entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      tamagotchi: descriptor
    };
    Service._openSettingsOwner("tamagotchi", function (owner) {
      try {
        check(owner, "actual native owner");
        api = Service.createPluginAPI("tamagotchi", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          tamagotchi: {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("tamagotchi", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expectations.reload();
    expectations.waitForJob();
    var expected = JSON.parse(expectations.text())[name];
    return Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared, scope === "instance" ? expected.bar.widgets.left[0].instanceSettings : {});
  }
  function ready(name) {
    var cfg = values(name), target = scope === "instance" ? selected : api;
    return ["difficulty", "volume", "showDebug", "showPercentage"].every(key => JSON.stringify(target.pluginSettings[key]) === JSON.stringify(cfg[key]));
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_GAME_DISK"), casePath, Quickshell.env("PHA_GAME_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var difficulty = find(popup.settingsPage, item => item.objectName === "settings-range-editDifficulty");
    var volume = find(popup.settingsPage, item => item.objectName === "settings-range-editVolume");
    var debug = find(popup.settingsPage, item => item.label === api.tr("settings.debug") && item.toggled !== undefined);
    var percentage = find(popup.settingsPage, item => item.label === api.tr("settings.percentage") && item.toggled !== undefined);
    check(difficulty && volume && debug && percentage, "all four actual game controls");
    difficulty.value = 0;
    difficulty.moved();
    volume.value = 0.25;
    volume.moved();
    debug.toggled(false);
    percentage.toggled(false);
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function consumers(name) {
    var cfg = values(name), game = oldRed ? main : main.gameFor(scope === "instance" ? selected : api);
    check(game && game.difficulty === cfg.difficulty, oldRed ? "original game consumes saved selected difficulty" : "game consumes selected difficulty");
    check(bar._minStat === Math.min(cfg.hunger, cfg.happiness, cfg.cleanliness), "actual Bar selected minimum stat");
    check(find(bar, item => item.text === bar._minStat + "%"), "actual Bar stat Text");
    check(find(panel, item => item.hunger !== undefined && item.energy !== undefined && item.hunger === cfg.hunger && item.energy === cfg.energy), "actual Panel selected stat model");
    check(find(panel, item => item.text === cfg.hunger + "%" && item.opacity === (cfg.showPercentage ? 1 : 0)), "actual Panel percentage Text");
    console.log("GAME_CONSUMER " + JSON.stringify({
                                                    boundary: name,
                                                    difficulty: game.difficulty,
                                                    minStat: bar._minStat,
                                                    hunger: game.hunger,
                                                    energy: game.energy
                                                  }));
    console.log("GAME_NATIVE: PASS " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native game phase");
    if (phase === "runtime" && selected.settingsReady) {
      var context = scope === "instance" ? selected : api;
      bar = create("barWidget", context);
      panel = create("panel", context);
      var ball = find(panel, item => item.gravity !== undefined && item.forceMultiplier !== undefined);
      check(ball, "actual Ball collaborator");
      ball.gravity = 0;
      ball.vx = 0;
      ball.vy = 0;
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "cold")
        consumers(boundary);
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty, "construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", "edited-consumers");
    else if (phase === "edited-consumers")
      consumers("edited");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.resetFields(["difficulty", "volume", "showDebug", "showPercentage"]), "one staged native Reset");
      phase = "reset-staging";
    } else if (phase === "reset-staging" && !popup.busy && ["difficulty", "volume", "showDebug", "showPercentage"].every(key => popup._pageApi.field(key).pendingIntent === "reset"))
      probe("reset-staged", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-consumers");
    else if (phase === "reset-consumers")
      consumers("reset");
    else if (phase === "change-base") {
      api.pluginSettings.difficulty = 100;
      api.pluginSettings.volume = 0.75;
      api.pluginSettings.showDebug = false;
      api.pluginSettings.showPercentage = false;
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "shared native propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-consumers");
    else if (phase === "following-consumers")
      consumers("following");
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
