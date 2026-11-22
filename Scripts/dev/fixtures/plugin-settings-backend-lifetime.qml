import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_BACKEND_PLUGIN")
  readonly property bool original: Quickshell.env("PHA_BACKEND_ORIGINAL") === "1"
  readonly property string variant: Quickshell.env("PHA_BACKEND_VARIANT")
  readonly property string base: Quickshell.env("PHA_BACKEND_CASE")
  property var api: null
  property var placed: null
  property var main: null
  property var bars: []
  property var panel: null
  property var backend: null
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  property var capturedContext: null
  property var syntheticCfg: ({
                                refreshInterval: 1234.6
                              })
  property bool syntheticCurrent: true
  property var syntheticClient: null
  property QtObject syntheticContext: QtObject {
    readonly property var settingsView: root.syntheticCfg
    readonly property bool alive: root.syntheticCurrent
    function current() {
      return alive;
    }
  }
  property int typedInterval: syntheticCfg.refreshInterval ?? 3000
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  PanelWindow {
    visible: true
    implicitWidth: 1400
    implicitHeight: 900
    Item {
      id: content
      width: 1400
      height: 900
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("BACKEND_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(plugin + "/" + phase + ": " + String(error));
    if (error && error.stack)
      console.error(error.stack);
    Qt.exit(2);
  }
  function find(object, predicate, seen) {
    if (!object)
      return null;
    seen = seen || new Set();
    if (seen.has(object))
      return null;
    seen.add(object);
    if (predicate(object))
      return object;
    for (const list of [object.data, object.children, object.instances]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (let i = 0; i < list.length; i++) {
        const result = find(list[i], predicate, seen);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(entry, context) {
    const component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    const item = PluginLoader.createObject(plugin, entry, component, content, context, entry === "barWidget" ? {
                                                                                                                 screen: Quickshell.screens[0]
                                                                                                               } : {});
    check(item, "actual " + entry);
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), words = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, words, words, {});
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        if (descriptor.entryPoints.main) {
          main = create("main", api);
          api.mainInstance = main;
        }
        placed = PluginInstances.apiFor(plugin, {
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
  function popupBackend() {
    return plugin === "auto-cpufreq" ? panel.main : panel.mainWidget;
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function action(held) {
    capturedContext = placed.settingsContext;
    if (plugin === "auto-cpufreq") {
      const button = find(panel, item => item.icon === (held ? "bolt" : "gauge") && typeof item.clicked === "function" && item.showDivider === false);
      check(button, "actual CPU action button");
      button.clicked();
    } else if (plugin === "thinkpad-fan") {
      const button = find(panel, item => item.level === (held ? "7" : "3") && typeof item.clicked === "function");
      check(button, "actual fan action button");
      button.clicked(null);
    } else {
      const slider = find(panel, item => item.from === 50 && item.to === 100 && typeof item.moved === "function");
      check(slider, "actual threshold slider");
      slider.value = held ? 95 : 75;
      slider.moved();
    }
  }
  function drive() {
    check(Date.now() - since < 15000, "finite backend phase");
    if (phase === "runtime" && placed.settingsReady) {
      bars = [create("barWidget", placed), create("barWidget", placed)];
      panel = create("panel", placed);
      phase = "observed";
    } else if (phase === "observed" && Date.now() - since > 700) {
      backend = popupBackend();
      check(backend, "popup has a backend before renderer retirement");
      if (!original) {
        check(backend === main.settingsConsumerFor(placed.settingsContext), "popup selected context client");
        check(bars.every(bar => bar.settingsConsumer === backend), "same API shares client across renderers");
        check(api.mainInstance === main && placed.mainInstance === main, "renderers never replace Main");
      }
      bars[1].destroy();
      bars = [bars[0]];
      phase = "retired-renderer";
    } else if (phase === "retired-renderer" && Date.now() - since > 400) {
      check(popupBackend() !== null && popupBackend() === backend, "popup backend survives last renderer retirement");
      if (plugin === "auto-cpufreq") {
        check(backend.sourceInterval === 1700 && backend.interval === 1700, "selected actual typed polling client");
        check(bars[0].compact, "selected compact Bar");
        check(find(panel, item => item.text === "powersave"), "actual popup governor Text");
      } else if (plugin === "battery-and-power-management") {
        check(backend.devicePath.endsWith("/BAT1"), "selected battery device");
        check(backend.batPercent === 64, "selected battery observation");
        check(find(panel, item => item.text === "64%"), "actual popup battery Text");
      } else {
        check(Qt.colorEqual(backend.colorAuto, "#445566"), "selected popup automatic palette");
        const button = find(panel, item => item.level === "auto" && item.stateColor !== undefined);
        check(button && Qt.colorEqual(button.stateColor, "#445566"), "actual popup selector palette");
      }
      if (variant === "actions") {
        action(false);
        phase = "action-complete";
      } else {
        panel.destroy();
        bars[0].destroy();
        phase = "no-renderers";
      }
    } else if (phase === "action-complete" && Date.now() - since > 400) {
      if (plugin === "auto-cpufreq")
        check(backend.governor === "performance", "actual governor readback after action");
      else if (plugin === "thinkpad-fan")
        check(backend.fanLevel === "3", "actual fan level readback");
      else
        check(backend.batteryThreshold === 75, "selected threshold action");
      action(true);
      phase = "held-action";
    } else if (phase === "held-action" && Date.now() - since > 250) {
      check(rows().some(row => row.name === (plugin === "auto-cpufreq" ? "pkexec" : "sh") && row.argv.some(value => value.indexOf(plugin === "auto-cpufreq" ? "--turbo=always" : plugin === "thinkpad-fan" ? "echo level 7" : "echo 95") !== -1)), "actual held action endpoint");
      panel.destroy();
      bars[0].destroy();
      placed.destroy();
      phase = "retired-action";
    } else if (phase === "retired-action" && Date.now() - since > 300) {
      const count = rows().length;
      if (plugin === "auto-cpufreq")
        main.setForce("powersave", capturedContext);
      else if (plugin === "thinkpad-fan")
        main.setFanSpeed("2", capturedContext);
      else
        main.setPowerProfile("power-saver", capturedContext);
      check(rows().length === count, "retired action refused synchronously");
      phase = "retired-context";
    } else if (phase === "no-renderers" && Date.now() - since > 300) {
      panel = create("panel", placed);
      check(popupBackend() === backend, "popup without a Bar keeps the same backend");
      panel.destroy();
      placed.destroy();
      phase = "retired-context";
    } else if (phase === "retired-context" && Date.now() - since > 400) {
      check(main._settingsConsumers.size === 1, "retired context leaves only shared client");
      if (variant === "source" && plugin !== "thinkpad-fan") {
        syntheticCfg = plugin === "auto-cpufreq" ? {
                                                     refreshInterval: 1234.6
                                                   } : {
          batteryDevice: base + "/hardware/sys/class/power_supply/BAT1"
        };
        syntheticClient = main.settingsConsumerFor(syntheticContext);
        phase = "synthetic";
      } else {
        main.destroy();
        main = null;
        phase = "joined";
      }
    } else if (phase === "synthetic" && Date.now() - since > 250) {
      if (plugin === "auto-cpufreq") {
        const timer = find(syntheticClient, item => item.repeat === true && item.triggeredOnStart === true);
        check(timer && timer.interval === typedInterval && syntheticClient.sourceInterval === typedInterval, "original QML int interval domain");
        syntheticCfg = {
          refreshInterval: 0
        };
        phase = "zero";
      } else {
        check(rows().some(row => row.name === "upower" && row.argv[1].endsWith("BAT1")), "actual held old battery ETA");
        check(syntheticClient.observation !== main.settingsConsumer.observation, "different device has its own physical reader");
        syntheticCfg = {
          batteryDevice: base + "/hardware/sys/class/power_supply/BAT0"
        };
        phase = "source-replaced";
      }
    } else if (phase === "zero") {
      const timer = find(syntheticClient, item => item.repeat === true && item.triggeredOnStart === true);
      check(timer && timer.interval === 0 && timer.running, "original zero polling admission " + JSON.stringify({
                                                                                                                  timerInterval: timer?.interval,
                                                                                                                  running: timer?.running,
                                                                                                                  sourceInterval: syntheticClient.sourceInterval,
                                                                                                                  current: syntheticClient.current,
                                                                                                                  source: syntheticCfg
                                                                                                                }));
      syntheticCurrent = false;
      phase = "synthetic-retired";
    } else if (phase === "source-replaced" && Date.now() - since > 250) {
      check(syntheticClient.observation === main.settingsConsumer.observation && main._batterySources.size === 1, "same device has one owner; old subscription released");
      check(syntheticClient.batPercent === 64 && syntheticClient.timeRemaining === "2h 0m", "replacement observation excludes held old response");
      syntheticCurrent = false;
      phase = "synthetic-retired";
    } else if (phase === "synthetic-retired" && Date.now() - since > 250) {
      check(main._settingsConsumers.size === 1, "synthetic client retirement");
      main.destroy();
      main = null;
      phase = "joined";
    } else if (phase === "joined" && Date.now() - since > 300) {
      driver.stop();
      console.log("BACKEND_LIFETIME: PASS " + plugin);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    id: driver
    interval: 40
    running: true
    repeat: true
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
