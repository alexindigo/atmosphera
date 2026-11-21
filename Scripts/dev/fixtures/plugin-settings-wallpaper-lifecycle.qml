import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_WALLPAPER_CASE")
  readonly property string scenario: Quickshell.env("PHA_WALLPAPER_LIFETIME")
  readonly property string screenName: Quickshell.env("PHA_WALLPAPER_SCREEN")
  readonly property string plugin: "linux-wallpaperengine-controller"
  property bool started: false
  property var api: null
  property var target: null
  property var context: null
  property var main: null
  property var client: null
  property string phase: "owner"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string afterDisk: ""
  property int engineCount: 0
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
        root.fail("independent native documents differ");
      else
        root.phase = root.afterDisk;
    }
  }
  Process {
    id: control
    onExited: code => {
      if (code !== 0)
        root.fail("inert control failed");
    }
  }
  Item {
    id: content
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WALLPAPER_LIFETIME_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function rows(name) {
    requests.reload();
    requests.waitForJob();
    const all = String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
    return name ? all.filter(row => row.endpoint === name) : all;
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
        check(["saved", "nothing_to_save"].includes(result.status), "selected native save");
        Service.waitForPluginSaves(api, result => {
          try {
            check(["saved", "nothing_to_save"].includes(result.status), "shared native save");
            phase = next;
          } catch (error) {
            fail(error);
          }
        }, false);
      } catch (error) {
        fail(error);
      }
    }, false);
  }
  function retire(next) {
    const entries = Settings.store.copyValue(Settings.data.bar.widgets.left);
    entries[0].id = "plugin:retired-wallpaper";
    Settings.data.bar.widgets.left = entries;
    phase = "retiring";
    Settings.saveSelected([["bar", "widgets", "left"]], result => {
      try {
        check(["saved", "nothing_to_save"].includes(result.status), "native owner replacement");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    const descriptor = JSON.parse(manifest.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "native LWE owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, {}, {}, {});
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = component.createObject(content, {
                                        pluginApi: api
                                      });
        check(main, "actual Main");
        api.mainInstance = main;
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
    check(Date.now() - since < 18000, "finite lifetime phase deadline");
    if (phase === "ready" && target.settingsReady && !main.checkingEngine) {
      if (scenario === "engine") {
        main.reload(false, context);
        phase = "engine";
      } else if (scenario === "source") {
        client = main.settingsConsumerFor(context);
        check(client !== main.sharedCatalog && main.settingsConsumerFor(context) === client, "context-keyed singular browse client");
        client.refresh(true, false);
        phase = "source";
      } else {
        main.scheduleWallpaperColorsFromPath(base + "/color-original", {
                                               screenName: screenName
                                             }, context);
        target.pluginSettings.defaultFps = 37;
        target.saveSettings();
        api.pluginSettings.wallpaperProperties = {
          "color-original": {
            tint: "new"
          }
        };
        api.saveSettings();
        phase = "color";
      }
    } else if (phase === "engine" && rows("linux-wallpaperengine").length) {
      const command = rows("linux-wallpaperengine")[0].argv;
      check(command[command.indexOf("--fps") + 1] === "29", "admitted selected engine fps");
      api.pluginSettings.screens = {
        [screenName]: {
          path: base + "/newer-wallpaper"
        }
      };
      api.saveSettings();
      target.pluginSettings.defaultFps = 37;
      target.saveSettings();
      settle("stable");
    } else if (phase === "stable" && api.pluginSettings.lastKnownGoodScreens[screenName]?.path === base + "/original-wallpaper") {
      check(main.enginePolicy.options.defaultFps === 29, "stability keeps admitted policy");
      settle("stable-disk");
    } else if (phase === "stable-disk")
      probe("stable", "crash");
    else if (phase === "crash") {
      main.activatePolicy(api.settingsContext);
      control.command = ["touch", base + "/fail-engine"];
      control.running = true;
      phase = "recovery";
    } else if (phase === "recovery" && rows("linux-wallpaperengine").length === 2) {
      const command = rows("linux-wallpaperengine")[1].argv;
      check(command[command.indexOf("--fps") + 1] === "29" && command.includes(base + "/original-wallpaper"), "real failed process recovers original origin/options/layout");
      check(main.enginePolicy.context === context, "recovery retains admitted runtime context");
      settle("recovered-disk");
    } else if (phase === "recovered-disk")
      probe("recovered", "retire");
    else if (phase === "source" && client.cachedWallpaperItems.length) {
      check(client.cachedWallpaperItems[0].path === base + "/selected-folder/controlled", "selected source result");
      target.pluginSettings.wallpapersFolder = base + "/held-source";
      target.saveSettings();
      phase = "held-source";
    } else if (phase === "held-source" && rows("scan-wallpapers.sh").some(row => row.argv[0] === base + "/held-source")) {
      target.pluginSettings.wallpapersFolder = base + "/replacement-folder";
      target.saveSettings();
      phase = "replacement";
    } else if (phase === "replacement" && client.cachedWallpaperItems[0]?.path === base + "/replacement-folder/controlled") {
      check(!client.scanningWallpapers, "replacement scan completed");
      check(main.sharedCatalog.cachedWallpaperItems.every(row => row.path.startsWith(base + "/shared-folder/")), "shared source is independent");
      settle("replaced-disk");
    } else if (phase === "replaced-disk")
      probe("replaced", "retire");
    else if (phase === "color" && api.pluginSettings.wallpaperColorScreenshots[screenName]) {
      const captures = rows("capture-wallpaper-colors.sh");
      check(captures.length === 1, "one capture owner");
      const command = captures[0].argv;
      check(command[command.indexOf("--fps") + 1] === "29" && command.includes("tint=old") && command.includes(base + "/color-original"), "delayed color uses captured typed inputs/property content");
      settle("color-disk");
    } else if (phase === "color-disk")
      probe("color", "retire-color");
    else if (phase === "retire-color") {
      main.scheduleWallpaperColorsFromPath(base + "/retired-color", {
                                             screenName: screenName
                                           }, context);
      retire("retired");
    } else if (phase === "retire")
      retire("retired");
    else if (phase === "retired" && !context.current() && Date.now() - since > 3200) {
      check(!main.tryAutoRecoverFromRuntimeError("retired"), "retired context cannot recover/publish");
      if (scenario === "source")
        check(!main.catalogClients.has(context), "retired source client removed");
      if (scenario === "color")
        check(rows("capture-wallpaper-colors.sh").length === 1, "retired color timer cannot capture/publish");
      probe("retired", "finish");
    } else if (phase === "finish") {
      main.stopAll();
      control.command = ["touch", base + "/release-engine", base + "/release-scan"];
      control.running = true;
      phase = "join";
    } else if (phase === "join" && !control.running) {
      console.log("WALLPAPER_LIFETIME: PASS " + scenario);
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
