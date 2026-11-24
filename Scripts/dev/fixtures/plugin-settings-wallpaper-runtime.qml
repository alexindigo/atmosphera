// Actual Main consumers with inert endpoints and explicit read-only contexts.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_WALLPAPER_PLUGIN")
  readonly property string base: Quickshell.env("PHA_WALLPAPER_CASE")
  readonly property bool original: Quickshell.env("PHA_WALLPAPER_ORIGINAL") === "1"
  readonly property bool browse: Quickshell.env("PHA_WALLPAPER_BROWSE") === "1"
  property var main: null
  property bool current: true
  property string phase: "startup"
  property double since: Date.now()
  property int savedAtRetirement: 0
  property var browseEvents: []
  onPhaseChanged: since = Date.now()
  FileView {
    id: manifest
    path: root.base + "/plugin/manifest.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: gate
  }
  QtObject {
    id: shared
    property var manifest: null
    property string pluginDir: root.base + "/plugin"
    property var mainInstance: root.main
    property int saves: 0
    property var settingsContext: null
    property var pluginSettings: QtObject {
      property bool active: false
      property bool enabled: false
      property bool automation: false
      property string activeBackend: "mpvpaper"
      property bool autoApplyOnStartup: false
      property int defaultFps: 13
      property string wallpapersFolder: root.base + "/shared"
      property string currentWallpaper: ""
      property string mpvSocket: root.base + "/socket"
      property var screens: ({})
      property var monitors: ({})
      property var lastKnownGoodScreens: ({})
      property var wallpaperProperties: ({})
      property var wallpaperColorScreenshots: ({})
      property bool runtimeRecoveryPending: false
      property var oldWallpapers: ({})
      property bool thumbCacheReady: false
      property bool isPlaying: false
      property double volume: 23
    }
    function tr(key) {
      return key;
    }
    function saveSettings(callback) {
      ++saves;
      if (callback)
        Qt.callLater(() => callback({
                                      status: "saved",
                                      refreshState: "current"
                                    }));
      return true;
    }
    function withCurrentScreen(callback) {
      callback(Quickshell.screens[0]);
    }
    function recordBrowse(event, value) {
      root.browseEvents.push({
                               event: event,
                               value: value
                             });
    }
  }
  QtObject {
    id: selected
    property var manifest: shared.manifest
    property string pluginDir: shared.pluginDir
    property var mainInstance: root.main
    property int saves: 0
    property var settingsContext: null
    property var pluginSettings: QtObject {
      property bool active: true
      property bool enabled: true
      property bool automation: false
      property string activeBackend: "mpvpaper"
      property bool autoApplyOnStartup: false
      property int defaultFps: 29
      property string wallpapersFolder: root.base + "/selected"
      property string currentWallpaper: ""
      property string mpvSocket: root.base + "/selected-socket"
      property var monitors: ({})
      property bool isPlaying: false
      property double volume: 47
    }
    function tr(key) {
      return key;
    }
    function saveSettings(callback) {
      ++saves;
      if (callback)
        Qt.callLater(() => callback({
                                      status: "saved",
                                      refreshState: "current"
                                    }));
      return true;
    }
    function withCurrentScreen(callback) {
      callback(Quickshell.screens[0]);
    }
  }
  function context(api, selectedOrigin) {
    const result = {
      current: function () {
        return !selectedOrigin || root.current;
      }
    };
    Object.defineProperty(result, "settingsView", {
                            get: function () {
                              const values = {};
                              for (const key of ["active", "enabled", "automation", "activeBackend", "autoApplyOnStartup", "defaultFps", "wallpapersFolder", "currentWallpaper", "mpvSocket", "monitors", "isPlaying", "volume"])
                                values[key] = api.pluginSettings[key];
                              return Object.freeze(values);
                            }
                          });
    return Object.freeze(result);
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("WALLPAPER_RUNTIME_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function begin() {
    if (phase !== "startup" || !Settings.isLoaded)
      return;
    manifest.waitForJob();
    shared.manifest = JSON.parse(manifest.text());
    shared.settingsContext = context(shared, false);
    selected.settingsContext = context(selected, true);
    const screen = Quickshell.screens[0].name;
    shared.pluginSettings.screens = {
      [screen]: {
        path: base + "/shared/wallpaper"
      }
    };
    const component = Qt.createComponent("file://" + base + "/plugin/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: shared
                                  });
    check(main, "actual Main constructs");
    phase = "ready";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite phase deadline");
    if (phase === "ready") {
      if (browse) {
        if (Date.now() - since < 400)
          return;
        if (plugin === "mpvpaper")
          main.random(selected);
        else
          main.random(Quickshell.screens[0].name, selected);
        phase = "browse-writer";
        return;
      }
      if (plugin === "linux-wallpaperengine-controller") {
        if (main.checkingEngine)
          return;
        main.reload(false, selected.settingsContext);
        phase = "engine";
      } else {
        if (plugin === "mpvpaper")
          main.setWallpaper(base + "/selected/controlled.mp4", selected);
        else
          main.setWallpaper(base + "/selected/controlled.mp4", Quickshell.screens[0].name, selected);
        phase = "writer";
      }
    } else if (phase === "browse-writer" && selected.saves > 0) {
      const screen = Quickshell.screens[0].name;
      const path = plugin === "mpvpaper" ? selected.pluginSettings.currentWallpaper : selected.pluginSettings.monitors[screen]?.currentWallpaper;
      const sharedPath = plugin === "mpvpaper" ? shared.pluginSettings.currentWallpaper : shared.pluginSettings.monitors[screen]?.currentWallpaper;
      check(path === base + "/selected/controlled.mp4" && !sharedPath && selected.saves > 0, "selected browse source and runtime writer");
      selected.pluginSettings.wallpapersFolder = base + "/replacement";
      savedAtRetirement = selected.saves;
      browseEvents = [];
      if (plugin === "mpvpaper")
        main.nextWallpaper(selected);
      else
        main.nextWallpaper(screen, selected);
      const admitted = browseEvents[0];
      const request = admitted?.value.request;
      check(browseEvents.length === 1 && admitted?.event === "admitted" && request?.folder === base + "/replacement" && admitted.value.source === request.folder && request.mode === "next" && request.writer === selected && request.context === selected.settingsContext, "replacement browse was admitted with its exact source and selected writer");
      current = false;
      phase = "browse-retired";
    } else if (phase === "browse-retired" && browseEvents.some(row => row.event === "settled" && row.value === base + "/replacement")) {
      check(selected.saves === savedAtRetirement, "retired queued browse cannot publish to its native writer");
      gate.command = ["touch", base + "/release-engine"];
      gate.running = true;
      phase = "finish";
    } else if (phase === "writer") {
      const screen = Quickshell.screens[0].name;
      const path = plugin === "mpvpaper" ? selected.pluginSettings.currentWallpaper : selected.pluginSettings.monitors[screen]?.currentWallpaper;
      const sharedPath = plugin === "mpvpaper" ? shared.pluginSettings.currentWallpaper : shared.pluginSettings.monitors[screen]?.currentWallpaper;
      check(path === base + "/selected/controlled.mp4" && !sharedPath && selected.saves > 0, "wallpaper action writes only its originating configuration");
      phase = "engine";
    } else if (phase === "engine") {
      const endpoint = rows().find(row => row.endpoint === (plugin === "linux-wallpaperengine-controller" ? "linux-wallpaperengine" : "mpvpaper") && !row.argv.includes("--help"));
      if (!endpoint)
        return;
      if (plugin === "linux-wallpaperengine-controller")
        check(endpoint.argv[endpoint.argv.indexOf("--fps") + 1] === "29", "selected engine fps reaches inert endpoint");
      else
        check(endpoint.argv.join(" ").includes(base + "/selected/controlled.mp4"), "selected playback reaches actual inert backend");
      gate.command = ["touch", base + "/release-engine"];
      gate.running = true;
      phase = "finish";
    } else if (phase === "finish" && !gate.running) {
      main.destroy();
      main = null;
      console.log("WALLPAPER_RUNTIME: PASS " + plugin);
      Qt.exit(0);
    }
  }
  Item {
    id: content
  }
  Timer {
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      try {
        if (root.phase === "startup")
          root.begin();
        else
          root.drive();
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
}
