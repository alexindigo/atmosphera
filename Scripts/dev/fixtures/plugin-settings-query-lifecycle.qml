// Actual workers and child consumers; explicit contexts, not native placement proof.
import QtQuick
import Quickshell
import Quickshell.Io
import "Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_QUERY_PLUGIN")
  readonly property string caseDir: Quickshell.env("PHA_QUERY_CASE")
  property var main: null
  property var shared: null
  property var selected: null
  property var client: null
  property var sharedClient: null
  property var panel: null
  property var browser: null
  property var bar: null
  property var data: null
  property var capturedContext: null
  property string phase: "start"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  FileView {
    id: input
    path: root.caseDir + "/input.json"
    blockLoading: true
  }
  FileView {
    id: held
    path: root.caseDir + (root.plugin === "hassio" ? "/socket-held" : "/ping-held")
    blockLoading: true
  }
  FileView {
    id: oldEvent
    path: root.caseDir + "/mpris-old-event-done"
    blockLoading: true
  }
  Process {
    id: release
    command: ["touch", root.caseDir + "/release"]
  }
  Process {
    id: mprisEvent
    command: ["touch", root.caseDir + "/mpris-old-event"]
  }
  PanelWindow {
    visible: true
    implicitWidth: 600
    implicitHeight: 700
    Item {
      id: content
      anchors.fill: parent
    }
  }
  Component {
    id: apiFactory
    QtObject {
      id: api
      required property var pluginSettings
      property var manifest: root.data.manifest
      property string pluginDir: root.data.directory
      property var mainInstance: root.main
      property bool alive: true
      readonly property var settingsView: pluginSettings
      readonly property var settingsContext: Read.context(function () {
        return api.pluginSettings;
      }, function () {
        return api.alive;
      })
      function tr(key, params) {
        return key;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("QUERY_LIFECYCLE_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var result = find(child, predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(file, properties) {
    var comp = Qt.createComponent("file://" + data.directory + "/" + file);
    check(comp.status === Component.Ready, comp.errorString());
    var item = comp.createObject(content, properties);
    check(item !== null, "actual " + file + " constructs");
    return item;
  }
  function begin() {
    input.waitForJob();
    data = JSON.parse(input.text());
    shared = apiFactory.createObject(root, {
                                       pluginSettings: data.shared
                                     });
    selected = apiFactory.createObject(root, {
                                         pluginSettings: data.selected
                                       });
    main = create("Main.qml", {
                    pluginApi: shared
                  });
    sharedClient = main.settingsConsumerFor(shared.settingsContext);
    capturedContext = selected.settingsContext;
    client = main.settingsConsumerFor(capturedContext);
    check(client !== sharedClient, "distinct source clients");
    if (plugin === "mpris-lyric") {
      bar = create("BarWidget.qml", {
                     pluginApi: selected,
                     screen: Quickshell.screens[0]
                   });
    } else {
      panel = create("Panel.qml", {
                       pluginApi: selected,
                       width: 580,
                       height: 680
                     });
    }
    if (plugin === "hassio") {
      browser = find(panel, item => item._allEntities !== undefined);
      check(browser && browser.main === client, "actual Browser receives selected client");
    } else if (plugin === "latency-monitor") {
      bar = create("BarWidget.qml", {
                     pluginApi: selected,
                     screen: Quickshell.screens[0]
                   });
    }
    phase = "initial";
  }
  function heldReady() {
    held.reload();
    held.waitForJob();
    return held.text() !== "";
  }
  function replaceLatency() {
    var old = client.hosts[0];
    check(old._proc.running, "old actual ping is held");
    selected.pluginSettings = data.replacement;
    check(client.hostsCfg[0].address === "192.0.2.3" && client.intervalSeconds === 15, "new typed source is observed at handoff");
    check(!old.active && !old._timer.running && client.hosts.length === 0, "source replacement synchronously retires old Hosts");
    release.running = true;
    phase = "replacement";
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite phase deadline");
    if (phase === "start" && Settings.isLoaded)
      begin();
    else if (phase === "initial") {
      if (plugin === "mpris-lyric") {
        if (client.currentLyric !== "old lyric" || sharedClient.currentLyric !== "base lyric")
          return;
        check(bar.mainInstance === client && find(bar, item => item.text === "old lyric"), "actual selected MPRIS lyric Text");
        check(find(client, item => item.repeat === true && item.interval === 1500 && item.running), "actual selected MPRIS lyric Timer");
        selected.pluginSettings = data.replacement;
        phase = "mpris-replacement";
      } else if (plugin === "latency-monitor") {
        if (heldReady() && sharedClient.hosts[0]?.lastRtt === 5)
          replaceLatency();
      } else if (client.authenticated && sharedClient.authenticated && client.entities.count === 1) {
        panel.view = "browser";
        browser.load();
        phase = "browser-loaded";
      }
    } else if (phase === "mpris-replacement" && client.currentLyric === "new lyric") {
      check(client.targetPlayer.identity === "query-new" && find(bar, item => item.text === "new lyric"), "replacement actual player lyric reaches child Text");
      check(find(client, item => item.repeat === true && item.interval === 750 && item.running), "replacement MPRIS Timer uses selected interval");
      mprisEvent.running = true;
      phase = "mpris-old-event";
    } else if (phase === "mpris-old-event" && Date.now() - phaseStarted > 500) {
      oldEvent.reload();
      oldEvent.waitForJob();
      if (oldEvent.text() !== "delivered")
        return;
      check(client.currentLyric === "new lyric" && sharedClient.currentLyric === "base lyric", "old player metadata cannot overwrite selected or shared lyric");
      var menu = find(bar, item => item.triggered !== undefined && item.model !== undefined);
      check(menu, "actual MPRIS Bar action menu");
      menu.triggered("next", {});
      menu.triggered("previous", {});
      menu.triggered("play-pause", {});
      phase = "mpris-actions";
    } else if (phase === "mpris-actions" && !client.isPlaying) {
      selected.pluginSettings = Object.assign({}, data.replacement, {
                                                playerName: "absent-controlled-player"
                                              });
      phase = "mpris-missing";
    } else if (phase === "mpris-missing" && client.targetPlayer === null) {
      check(client.currentLyric === "" && client.trackTitle === "" && bar.displayText === "", "missing player clears source-specific result and rendered projection");
      selected.alive = false;
      phase = "retired";
    } else if (phase === "browser-loaded" && browser._allEntities.length === 1 && !browser._loading) {
      check(find(browser, item => item.text === "old entity"), "actual old browser row Text rendered");
      browser.load();
      phase = "browser-held";
    } else if (phase === "browser-held" && heldReady()) {
      selected.pluginSettings = data.replacement;
      check(client.haUrl === data.replacement.haUrl, "new typed socket source is observed at handoff");
      check(browser._allEntities.length === 0 && !browser._loading && !find(browser, item => item.text === "old entity" && item.visible), "source replacement clears browser cache and loading");
      release.running = true;
      phase = "replacement";
    } else if (phase === "replacement") {
      if (plugin === "latency-monitor") {
        if (client.hosts[0]?.lastRtt !== 80)
          return;
        check(client.hosts.length === 1 && client.hosts[0].address === "192.0.2.3" && client.hosts[0]._timer.interval === 15000, "settled new ping source and typed interval");
        check(find(bar, item => item.text === "New 80ms"), "actual replacement Bar Text");
        check(find(panel, item => item.text === "New"), "actual replacement Panel host Text");
        check(sharedClient.hosts[0].lastRtt === 5, "shared ping unaffected");
        var old = client.hosts[0];
        selected.pluginSettings = Object.assign({}, data.replacement, {
                                                  intervalSeconds: 20
                                                });
        check(client.intervalSeconds === 20, "new typed interval is observed at handoff");
        check(!old.active && client.hosts.length === 0, "interval-only replacement immediately fences Hosts");
        phase = "interval-replaced";
      } else {
        if (!client.authenticated || browser._loading || browser._allEntities.length !== 1 || browser._allEntities[0].entity_id !== "sensor.new")
          return;
        check(find(browser, item => item.text === "new entity"), "actual replacement Browser row Text");
        check(!find(browser, item => item.text === "old entity"), "held old socket cannot repopulate Browser");
        check(client.entities.count === 1 && client.entities.get(0).entity_id === "sensor.new", "selected pinned model uses new source");
        check(sharedClient.entities.get(0).entity_id === "sensor.shared", "shared socket unaffected");
        selected.pluginSettings = Object.assign({}, data.replacement, {
                                                  haToken: "next-fake-token",
                                                  entities: ["sensor.next"]
                                                });
        check(client.haToken === "next-fake-token", "new typed token is observed at handoff");
        check(browser._allEntities.length === 0 && !browser._loading, "token-only handoff clears browser state");
        phase = "token-replaced";
      }
    } else if (phase === "token-replaced" && client.authenticated && !browser._loading && browser._allEntities[0]?.entity_id === "sensor.next") {
      check(find(browser, item => item.text === "next entity"), "actual token-only replacement Browser row Text");
      client.callService("sensor", "controlled", "sensor.next");
      phase = "settled";
    } else if (phase === "interval-replaced" && client.hosts[0]?.lastRtt === 80) {
      check(client.hosts[0]._timer.interval === 20000, "interval replacement uses settled typed input");
      phase = "settled";
    } else if (phase === "settled" && Date.now() - phaseStarted > 500) {
      if (plugin === "hassio") {
        check(browser._allEntities[0]?.entity_id === "sensor.next", "late old reply cannot replace new browser result");
        selected.pluginSettings = Object.assign({}, data.replacement, {
                                                  haUrl: ""
                                                });
        check(browser._allEntities.length === 0 && !browser._loading, "incomplete source clears browser result");
      }
      selected.alive = false;
      phase = "retired";
    } else if (phase === "retired" && Date.now() - phaseStarted > 500) {
      check(!main._settingsConsumers.has(capturedContext), "retired source client leaves cache");
      if (plugin === "hassio")
        check(browser._allEntities.length === 0 && !browser._loading, "retired Browser cannot retain results or pending state");
      console.log("QUERY_LIFECYCLE: PASS " + plugin);
      Qt.exit(0);
    }
  }
  Timer {
    interval: 60
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error) + "\n" + (error.stack || ""));
        Qt.exit(2);
      }
    }
  }
}
