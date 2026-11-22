import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_NIRI_CASE")
  readonly property string scenario: Quickshell.env("PHA_NIRI_SCENARIO")
  readonly property bool tile: scenario.indexOf("auto-") === 0
  readonly property string plugin: tile ? "niri-auto-tile" : "niri-screensaver"
  property var main: null
  property var bar: null
  property bool started: false
  property int step: 0
  property double since: Date.now()
  property int expectedMax: Number(3.6)
  property int expectedDebounce: Number(250.9)
  property int expectedEvents: Number(12.7)
  onStepChanged: since = Date.now()
  function context(api) {
    return Object.freeze({
                           get settingsView() {
                             return api.values;
                           },
                           current: function () {
                             return api.alive;
                           }
                         });
  }
  QtObject {
    id: shared
    property var values: root.tile ? ({
                                        enabled: true,
                                        maxVisible: 4,
                                        onlyAtMax: true,
                                        perWorkspace: false,
                                        debounceMs: 300,
                                        maxEventsPerSecond: 20,
                                        workspaceMaxVisible: {}
                                      }) : ({
                                              enabled: true,
                                              idleSeconds: 300,
                                              frameRate: 60,
                                              launcherCommand: "shared-launch",
                                              killCommand: "shared-kill"
                                            })
    property bool alive: true
    readonly property var settingsContext: root.context(shared)
    readonly property var pluginSettings: values
    readonly property string pluginDir: root.base + "/config/plugins/" + root.plugin
    readonly property var manifest: ({
                                       metadata: {
                                         defaultSettings: {}
                                       }
                                     })
    property var mainInstance: root.main
    property int saves: 0
    function saveSettings() {
      values = Object.assign({}, values);
      saves++;
    }
    function tr(key) {
      return key;
    }
  }
  QtObject {
    id: selected
    property var values: root.tile ? ({
                                        enabled: true,
                                        maxVisible: 3,
                                        onlyAtMax: false,
                                        perWorkspace: false,
                                        debounceMs: 250,
                                        maxEventsPerSecond: 12,
                                        workspaceMaxVisible: {}
                                      }) : ({
                                              enabled: true,
                                              idleSeconds: 450,
                                              batteryMinPercent: 20,
                                              frameRate: 24,
                                              includeEffects: "rain,$literal",
                                              excludeEffects: "worm",
                                              fadeInEffect: "expand",
                                              fadeOutEffect: "burn",
                                              showClock: true,
                                              clockDuration: 7,
                                              clockFormat: "%H:%M",
                                              clockFont: "small",
                                              showNowPlaying: true,
                                              nowPlayingDuration: 9,
                                              logoPath: "/owned/logo.txt",
                                              cursorHide: false,
                                              cursorWarp: true,
                                              dismissOnKey: false,
                                              randomLogo: true,
                                              logoDir: "/owned/logos",
                                              multiMonitorMode: "mirror",
                                              launcherCommand: "selected-launch 'literal argument'",
                                              killCommand: "selected-kill 'stop argument'"
                                            })
    property bool alive: true
    readonly property var settingsContext: root.context(selected)
    readonly property var pluginSettings: values
    readonly property string pluginDir: shared.pluginDir
    readonly property var manifest: shared.manifest
    property var mainInstance: root.main
    property int saves: 0
    function saveSettings() {
      values = Object.assign({}, values);
      saves++;
    }
    function tr(key) {
      return key;
    }
  }
  QtObject {
    id: other
    property var values: root.tile ? ({
                                        enabled: true,
                                        maxVisible: 6,
                                        onlyAtMax: true,
                                        debounceMs: 700,
                                        maxEventsPerSecond: 30,
                                        workspaceMaxVisible: {}
                                      }) : ({
                                              enabled: true,
                                              idleSeconds: 900,
                                              frameRate: 48,
                                              launcherCommand: "other-launch",
                                              killCommand: "other-kill"
                                            })
    property bool alive: true
    readonly property var settingsContext: root.context(other)
  }
  Process {
    id: release
    command: ["touch", root.base + "/release-probe", root.base + "/release-config"]
  }
  PanelWindow {
    visible: true
    implicitWidth: 300
    implicitHeight: 300
    Item {
      id: content
      width: 300
      height: 300
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("NIRI_LIFETIME_ASSERT: " + scenario + "/" + step + ": " + message);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    if (!tile) {
      Settings.data.hooks.screenLock = "user-hook";
      Settings.data.hooks.screenUnlock = "";
    }
    const component = Qt.createComponent("file://" + shared.pluginDir + "/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: shared
                                  });
    check(main, "actual Main");
    if (scenario === "auto-typed")
      selected.values = Object.assign({}, selected.values, {
                                        maxVisible: 3.6,
                                        debounceMs: 250.9,
                                        maxEventsPerSecond: 12.7,
                                        perWorkspace: true,
                                        workspaceMaxVisible: {
                                          "1": 2
                                        }
                                      });
    check(main.applySettings(selected.settingsContext), "selected automatic admission");
    step = 1;
  }
  function drive() {
    if (step === 0)
      return;
    check(Date.now() - since < 15000, "finite lifetime phase");
    if (step === 1 && Date.now() - since > 2800) {
      if (tile) {
        check(main.running, "selected daemon running");
        if (scenario === "auto-typed") {
          check(main.maxVisible === expectedMax && main.debounceMs === expectedDebounce && main.maxEventsPerSecond === expectedEvents, "original int admission");
          check(main.getMaxVisibleForWorkspace(1, selected.settingsContext) === 2, "selected workspace map");
        } else if (scenario === "auto-hot") {
          main.setMaxVisible(2, selected);
          main.setPerWorkspace(true, selected);
          main.setWorkspaceMaxVisible(1, 2, selected);
          main.setOnlyAtMax(true, selected);
          check(selected.saves === 4 && shared.saves === 0, "originating writers only");
        } else if (scenario === "auto-restart") {
          main.applySettings(other.settingsContext);
          main.applySettings(selected.settingsContext);
        } else if (scenario === "auto-retire")
          selected.alive = false;
      } else {
        check(Settings.data.hooks.screenLock === "user-hook", "manual lock hook preserved");
        if (scenario === "screensaver-policy") {
          check(Settings.data.hooks.screenUnlock === "selected-kill 'stop argument'", "selected hook admitted");
          selected.values = Object.assign({}, selected.values, {
                                            killCommand: "other-kill"
                                          });
          main.applySettings(selected.settingsContext);
        } else if (scenario === "screensaver-config")
          main.applySettings(other.settingsContext);
        else {
          const component = Qt.createComponent("file://" + shared.pluginDir + "/BarWidget.qml");
          check(component.status === Component.Ready, component.errorString());
          bar = component.createObject(content, {
                                         pluginApi: selected,
                                         screen: Quickshell.screens[0]
                                       });
          check(bar, "actual Bar");
          bar._smartToggle();
        }
      }
      step = 2;
    } else if (step === 2 && Date.now() - since > 500) {
      if (!tile && (scenario === "screensaver-probe" || scenario === "screensaver-retire")) {
        selected.values = Object.assign({}, selected.values, {
                                          launcherCommand: "later-launch"
                                        });
        if (scenario === "screensaver-retire")
          selected.alive = false;
        else
          main.applySettings(other.settingsContext);
      }
      release.running = true;
      step = 3;
    } else if (step === 3 && Date.now() - since > 1800) {
      if (scenario === "auto-retire")
        check(!main.running, "retired daemon quiescent");
      if (scenario === "screensaver-policy")
        check(Settings.data.hooks.screenUnlock === "other-kill" && Settings.data.hooks.screenLock === "user-hook", "owned hook replacement only");
      console.log("NIRI_LIFETIME_RESULT " + JSON.stringify({
                                                             scenario: scenario,
                                                             maxVisible: tile ? main.maxVisible : null,
                                                             expectedMax: expectedMax,
                                                             expectedDebounce: expectedDebounce,
                                                             expectedEvents: expectedEvents,
                                                             selectedSaves: selected.saves,
                                                             sharedSaves: shared.saves,
                                                             idle: tile ? null : JSON.parse(Settings.data.idle.customCommands),
                                                             lock: tile ? null : Settings.data.hooks.screenLock,
                                                             unlock: tile ? null : Settings.data.hooks.screenUnlock
                                                           }));
      main.destroy();
      main = null;
      step = 4;
    } else if (step === 4 && Date.now() - since > 500) {
      driver.stop();
      console.log("NIRI_LIFETIME: PASS " + scenario);
      Qt.exit(0);
    }
  }
  SettingsBootstrap {}
  Connections {
    target: Settings
    function onSettingsLoaded() {
      try {
        root.begin();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
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
  Component.onCompleted: {
    try {
      begin();
    } catch (error) {
      fail(error);
    }
  }
}
