import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_WALLPAPER_CASE")
  readonly property string scenario: Quickshell.env("PHA_WALLPAPER_LIFETIME")
  readonly property string plugin: "video-wallpaper"
  readonly property var names: Quickshell.screens.map(screen => screen.name).sort()
  property bool started: false
  property var api: null
  property var target: null
  property var context: null
  property var main: null
  property var saveTimer: null
  property var receipt: null
  property string phase: "owner"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string afterDisk: ""
  property int firstBackendRows: 0
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete native Video documents differ");
      else
        root.phase = root.afterDisk;
    }
  }
  Process {
    id: release
    onExited: code => {
      if (code !== 0)
        root.fail("inert release failed");
    }
  }
  Item {
    id: content
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WALLPAPER_VIDEO_LIFETIME_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function component(path, props) {
    const c = Qt.createComponent("file://" + api.pluginDir + "/" + path);
    check(c.status === Component.Ready, c.errorString());
    const object = c.createObject(content, props);
    check(object, "actual " + path);
    return object;
  }
  function backends() {
    const found = [], seen = new Set();
    function visit(object) {
      if (!object || seen.has(object))
        return;
      seen.add(object);
      if (typeof object.buildMpvCommand === "function")
        found.push(object);
      if (object.item)
        visit(object.item);
      for (const list of [object.data, object.children, object.instances]) {
        if (!list || typeof list === "function" || typeof list.length !== "number")
          continue;
        for (const child of list)
          visit(child);
      }
    }
    visit(main);
    return found;
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line)).filter(row => row.endpoint === "mpvpaper" && !row.argv.includes("--help"));
  }
  function probe(boundary, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_WALLPAPER_DISK"), base, Quickshell.env("PHA_WALLPAPER_OUTPUT") + "/persisted", boundary];
    disk.running = true;
  }
  function settle(next) {
    phase = "settling";
    Service.waitForPluginSaves(target, result => {
      try {
        check(["saved", "nothing_to_save"].includes(result.status), "originating native result");
        phase = next;
      } catch (error) {
        fail(error);
      }
    }, false);
  }
  function retire() {
    const entries = Settings.store.copyValue(Settings.data.bar.widgets.left);
    entries[0].id = "plugin:retired-wallpaper";
    Settings.data.bar.widgets.left = entries;
    phase = "retiring";
    Settings.saveSelected([["bar", "widgets", "left"]], result => {
      try {
        check(["saved", "nothing_to_save"].includes(result.status), "native retirement publication");
        phase = "retired";
      } catch (error) {
        fail(error);
      }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    check(names.length === 2, "two actual compositor outputs");
    manifest.waitForJob();
    const descriptor = JSON.parse(manifest.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    WallpaperService.init();
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "native Video owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, {}, {}, {});
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        target = PluginInstances.apiFor(plugin, {
                                          kind: "bar",
                                          list: "global",
                                          section: "left",
                                          index: 0
                                        });
        context = target.settingsContext;
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    check(Date.now() - since < 18000, "finite Video phase deadline");
    if (phase === "ready" && target.settingsReady && WallpaperService.isInitialized) {
      if (scenario === "baseline") {
        saveTimer = component("common/SaveTimer.qml", {
                                pluginApi: target,
                                screenName: names[0]
                              });
        saveTimer.completed.connect(result => {
          receipt = result;
        });
        saveTimer.save("noctaliaWallpaper", base + "/captured-baseline", "captured");
        saveTimer.pluginApi = api;
        saveTimer.screenName = names[1];
        phase = "baseline";
      } else {
        main = component("Main.qml", {
                           pluginApi: api
                         });
        api.mainInstance = main;
        check(main.admitRuntime(target) === target, "actual runtime origin admitted");
        phase = scenario;
      }
    } else if (phase === "automation" && target.pluginSettings.monitors[names[0]].currentWallpaper === base + "/selected-folder/controlled.mp4") {
      check(target.pluginSettings.monitors[names[1]].currentWallpaper === base + "/selected-1.mp4", "disabled output automation retains its own path");
      check(main.activatePolicy(api.settingsContext), "explicitly quiesce automatic admission after the observed action");
      settle("applied-disk");
    } else if (phase === "backend" && Date.now() - since > 700 && backends().length === 2 && rows().length >= 2) {
      for (const name of names) {
        const backend = backends().find(item => item.screenName === name);
        check(backend && backend.settingsContext === context, "one selected physical backend per output");
        const row = rows().filter(row => row.argv.includes(name)).pop();
        check(row && row.argv.includes(backend.currentWallpaper) && row.argv.join(" ").includes("profile='" + backend.profile + "'"), "selected output command reaches inert backend");
      }
      firstBackendRows = rows().length;
      target.pluginSettings.activeBackend = "none";
      target.saveSettings();
      phase = "backend-off";
    } else if (phase === "backend-off" && Date.now() - since > 250 && backends().length === 0) {
      target.pluginSettings.activeBackend = "mpvpaper";
      target.saveSettings();
      phase = "backend-return";
    } else if (phase === "backend-return" && backends().length === 2 && rows().length >= firstBackendRows + 2)
      settle("applied-disk");
    else if (phase === "baseline" && receipt) {
      check(["saved", "nothing_to_save"].includes(receipt.status), "captured delayed native publication");
      check(target.pluginSettings.monitors[names[0]].noctaliaWallpaper === base + "/captured-baseline", "delayed body retains original screen/writer");
      settle("applied-disk");
    } else if (phase === "applied-disk")
      probe("applied", "retire");
    else if (phase === "retire") {
      if (scenario === "baseline") {
        saveTimer.pluginApi = target;
        saveTimer.screenName = names[0];
        saveTimer.save("noctaliaWallpaper", base + "/retired-baseline", "retired");
        saveTimer.running = false;
      }
      retire();
    } else if (phase === "retired" && !context.current() && Date.now() - since > 600) {
      if (scenario === "baseline") {
        saveTimer.running = true;
        phase = "retired-baseline";
      } else {
        check(scenario !== "backend" || backends().length === 0, "retired policy removes physical backends");
        if (scenario === "backend") {
          PluginInstances._dropPlugin(plugin);
          phase = "retired-api";
        } else
          probe("retired", "finish");
      }
    } else if (phase === "retired-api" && Date.now() - since > 150) {
      check(main.activatePolicy(api.settingsContext), "shared policy can be reselected after registered API destruction");
      check(main.runtimeWriter === api, "destroyed placement cannot poison shared writer lookup");
      probe("retired", "finish");
    } else if (phase === "retired-baseline" && Date.now() - since > 150) {
      check(!saveTimer.busy, "held retired baseline cannot publish");
      probe("retired", "finish");
    } else if (phase === "finish") {
      release.command = ["touch", base + "/release-engine"];
      release.running = true;
      phase = "join";
    } else if (phase === "join" && !release.running) {
      console.log("WALLPAPER_VIDEO_LIFETIME: PASS " + scenario);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 35
    running: true
    repeat: true
    onTriggered: {
      try {
        if (root.started)
          root.drive();
        else
          root.begin();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
