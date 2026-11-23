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
  property var seededPlayback: null
  property int playbackCursor: 0
  property bool playbackJoinStarted: false
  property bool playbackJoined: false
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
  FileView {
    id: expectations
    path: root.base + "/playback.json"
    blockLoading: true
  }
  Process {
    id: joinPlayback
    onExited: code => {
      if (code !== 0)
        root.fail("WALLPAPER_VIDEO_LIFETIME_ASSERT: " + root.scenario + "/" + root.phase + ": exact playback identities did not retire before release or expiry");
      else
        root.playbackJoined = true;
    }
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
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line)).filter(row => row.endpoint === "mpvpaper" && !row.argv.includes("--help") && !row.argv.includes("--list-properties"));
  }
  function playbackReady() {
    const current = backends();
    if (current.length !== names.length)
      return false;
    const admitted = rows().slice(playbackCursor);
    for (const row of admitted) {
      const policy = seededPlayback[row.argv[2]];
      check(row.argv.length === 4 && row.argv[0] === "-o" && policy && row.argv[3] === policy.path && row.argv[1].split(" ").includes("profile='" + policy.profile + "'"), "output endpoint matches seeded playback policy");
    }
    for (const name of names) {
      const members = current.filter(item => item.screenName === name);
      check(members.length === 1 && members[0].settingsContext === context, "one selected physical backend per output");
    }
    return names.every(name => admitted.some(row => row.argv[2] === name));
  }
  function waitForPlaybackRetirement() {
    const cohort = rows();
    playbackCursor = cohort.length;
    playbackJoinStarted = true;
    playbackJoined = false;
    joinPlayback.command = ["python3", "-c", "import json,sys,time;from pathlib import Path\nbase=Path(sys.argv[1]);rows=json.loads(sys.argv[2]);end=time.monotonic()+float(sys.argv[3])\n" + "def identity(row):return row['pid'],row['start']\n"
                            + "def live(row):\n try:return (Path('/proc')/str(row['pid'])/'stat').read_text().rsplit(') ',1)[1].split()[19]==row['start']\n except FileNotFoundError:return False\n" + "while any(map(live,rows)):\n if time.monotonic()>=end:raise SystemExit(1)\n time.sleep(.02)\n"
                            + "if (base/'release-engine').exists() or set(map(identity,rows)) & {identity(json.loads(line)) for line in (base/'expired-engines.jsonl').read_text().splitlines()}:raise SystemExit(2)", base, JSON.stringify(cohort), String(Math.max(0, 18000 - (Date.now() - since)) / 1000)];
    joinPlayback.running = true;
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
    expectations.waitForJob();
    seededPlayback = JSON.parse(expectations.text());
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
    check(Date.now() - since < 18000, joinPlayback.running ? "exact playback identities did not retire" : "finite Video phase deadline");
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
    } else if (phase === "backend" && playbackReady()) {
      target.pluginSettings.activeBackend = "none";
      target.saveSettings();
      phase = "backend-off";
    } else if (phase === "backend-off" && backends().length === 0) {
      if (!playbackJoinStarted)
        waitForPlaybackRetirement();
      if (!playbackJoined)
        return;
      check(rows().length === playbackCursor, "no playback is admitted during the backend-off drain");
      playbackJoinStarted = false;
      playbackJoined = false;
      target.pluginSettings.activeBackend = "mpvpaper";
      target.saveSettings();
      phase = "backend-return";
    } else if (phase === "backend-return" && playbackReady())
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
    } else if (phase === "retired" && !context.current() && (scenario === "backend" || Date.now() - since > 600)) {
      if (scenario === "baseline") {
        saveTimer.running = true;
        phase = "retired-baseline";
      } else {
        if (scenario === "backend") {
          if (backends().length !== 0)
            return;
          if (!playbackJoinStarted)
            waitForPlaybackRetirement();
          if (!playbackJoined)
            return;
          check(rows().length === playbackCursor, "no playback is admitted after placement retirement");
          PluginInstances._dropPlugin(plugin);
          check(main.activatePolicy(api.settingsContext), "shared policy can be reselected after registered API destruction");
          check(main.runtimeWriter === api, "destroyed placement cannot poison shared writer lookup");
          probe("retired", "finish");
        } else
          probe("retired", "finish");
      }
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
