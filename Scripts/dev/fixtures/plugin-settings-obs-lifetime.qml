import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_OBS_CASE")
  readonly property string scenario: Quickshell.env("PHA_OBS_SCENARIO")
  property var main: null
  property var client: null
  property var second: null
  property var bar: null
  property var center: null
  property var panel: null
  property string phase: "start"
  property string afterMarker: ""
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool alive: true
  property bool otherAlive: true
  property var config: ({
                          pollIntervalMs: 10000,
                          leftClickAction: "toggle-record",
                          launchBehavior: "normal",
                          autoCloseManagedObs: false,
                          openVideosAfterStop: true,
                          videosPath: "~/captured videos",
                          videosOpener: "obs-open",
                          showBarWhenReady: true
                        })
  property var otherConfig: ({
                               pollIntervalMs: 10000,
                               leftClickAction: "panel",
                               launchBehavior: "minimized-to-tray",
                               autoCloseManagedObs: true,
                               openVideosAfterStop: false,
                               videosPath: "/other",
                               videosOpener: "obs-new-open"
                             })
  readonly property int originalInterval: Math.max(750, Number(config.pollIntervalMs))
  property QtObject context: QtObject {
    readonly property var settingsView: root.config
    readonly property bool alive: root.alive
    function current() {
      return alive;
    }
  }
  property QtObject otherContext: QtObject {
    readonly property var settingsView: root.otherConfig
    readonly property bool alive: root.otherAlive
    function current() {
      return alive;
    }
  }
  readonly property var sharedContext: ({
                                          current: function () {
                                            return true;
                                          },
                                          settingsView: {
                                            pollIntervalMs: 10000,
                                            leftClickAction: "panel",
                                            launchBehavior: "minimized-to-tray",
                                            autoCloseManagedObs: true,
                                            openVideosAfterStop: false,
                                            videosPath: "/shared",
                                            videosOpener: "obs-new-open"
                                          }
                                        })
  property int selectedPanels: 0
  property int sharedPanels: 0
  property var toastRows: []
  property var heldToast: null
  property int priorProbes: 0
  property int priorToasts: 0
  property int actionIndex: 0
  property var actions: ["toggleRecord", "toggleReplay", "toggleStream", "saveReplay"]
  readonly property var api: ({
                                settingsContext: sharedContext,
                                pluginSettings: sharedContext.settingsView,
                                manifest: {
                                  metadata: {
                                    defaultSettings: {}
                                  }
                                },
                                tr: function (key) {
                                  return key;
                                },
                                mainInstance: main,
                                togglePanel: function () {
                                  root.sharedPanels++;
                                }
                              })
  readonly property var runtimeApi: ({
                                       settingsContext: context,
                                       pluginSettings: config,
                                       tr: api.tr,
                                       mainInstance: main,
                                       togglePanel: function () {
                                         root.selectedPanels++;
                                       }
                                     })
  PanelWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 900
    Item {
      id: content
      width: 900
      height: 900
    }
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: socketRows
    path: root.base + "/socket.jsonl"
    blockLoading: true
  }
  Process {
    id: marker
    onExited: code => {
      if (code !== 0)
        root.fail("fixture marker");
      else
        root.phase = root.afterMarker;
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toastRows = root.toastRows.concat([
                                               {
                                                 title: title,
                                                 label: actionLabel
                                               }
                                             ]);
      if (actionCallback)
        root.heldToast = actionCallback;
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OBS_LIFETIME_ASSERT " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  function records(kind) {
    const file = kind === "socket" ? socketRows : requests;
    file.reload();
    file.waitForJob();
    return file.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function count(endpoint) {
    return records("process").filter(row => row.endpoint === endpoint).length;
  }
  function requested(kind) {
    return records("socket").filter(row => row.request === kind).length;
  }
  function mutate(values, after) {
    afterMarker = after;
    phase = "marker";
    marker.command = ["/usr/bin/python3", "-B", "-c", "import json,sys;from pathlib import Path;b=Path(sys.argv[1]);[( (b/k).write_text(json.dumps(v) if isinstance(v,dict) else 'marker') if v is not False else (b/k).unlink(missing_ok=True)) for k,v in json.loads(sys.argv[2]).items()]", base, JSON.stringify(values)];
    marker.running = true;
  }
  function create(file, properties) {
    const component = Qt.createComponent("file://" + base + "/config/plugins/obs-control/" + file);
    check(component.status === Component.Ready, component.errorString());
    const item = component.createObject(content, properties);
    check(item, "actual " + file);
    return item;
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
    for (const list of [object.data, object.children]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (let i = 0; i < list.length; i++) {
        const item = find(list[i], predicate, seen);
        if (item)
          return item;
      }
    }
    return null;
  }
  function stop() {
    console.log("OBS_LIFETIME_OUTCOME " + JSON.stringify({
                                                           scenario: scenario,
                                                           toasts: toastRows,
                                                           selectedPanels: selectedPanels,
                                                           sharedPanels: sharedPanels,
                                                           managed: main.managedObsLaunch,
                                                           requests: records("process"),
                                                           socket: records("socket")
                                                         }));
    bar.destroy();
    center.destroy();
    panel.destroy();
    main.destroy();
    main = null;
    phase = "joined";
  }
  function replacePolicy() {
    config = Object.assign({}, otherConfig, {
                             leftClickAction: "toggle-stream"
                           });
  }
  function drive() {
    check(Date.now() - since < 12000, "finite lifetime phase");
    if (phase === "start") {
      main = create("Main.qml", {
                      pluginApi: api
                    });
      client = main.settingsConsumerFor(context);
      second = main.settingsConsumerFor(otherContext);
      check(client === main.settingsConsumerFor(context) && client !== second, "API-keyed client");
      bar = create("BarWidget.qml", {
                     pluginApi: runtimeApi,
                     screen: Quickshell.screens[0]
                   });
      center = create("ControlCenterWidget.qml", {
                        pluginApi: runtimeApi,
                        screen: Quickshell.screens[0]
                      });
      panel = create("Panel.qml", {
                       pluginApi: runtimeApi
                     });
      check(bar.service === client && center.service === client && panel.service === client, "all actual selected views");
      phase = "initial";
    } else if (phase === "initial" && main.websocket && main.obsRunning && !main.actionBusy) {
      if (scenario === "typed") {
        config = Object.assign({}, config, {
                                 pollIntervalMs: 751.6
                               });
        phase = "typed";
      } else if (scenario === "panel-origin") {
        config = Object.assign({}, config, {
                                 leftClickAction: "panel"
                               });
        phase = "panel";
      } else if (scenario.startsWith("launch") || scenario.startsWith("start-"))
        mutate({
                 running: false,
                 "hold-pidof": true
               }, "launch");
      else if (scenario === "online-actions")
        mutate({
                 "obs-state.json": {
                   recording: false,
                   replay: false,
                   streaming: false,
                   camera: false
                 }
               }, "online");
      else if (scenario === "failure")
        mutate({
                 "obs-state.json": {
                   recording: false,
                   replay: false,
                   streaming: false,
                   camera: false
                 },
                 "fail-StartRecord": true
               }, "online");
      else {
        main.managedObsLaunch = scenario.startsWith("auto") || scenario.startsWith("terminate") || scenario.startsWith("confirm");
        const hold = scenario === "request-retire" ? "GetRecordStatus" : scenario === "auto-retire" ? "GetVirtualCamStatus" : scenario === "terminate-retire" ? "pkill" : "StopRecord";
        const changes = {
          ["hold-" + hold]: true
        };
        if (scenario === "auto-failure")
          changes["fail-GetStreamStatus"] = true;
        mutate(changes, "stop-action");
      }
    } else if (phase === "typed") {
      console.log("OBS_TYPED " + JSON.stringify({
                                                  original: originalInterval,
                                                  selected: client.pollIntervalMs,
                                                  timer: client.pollTimer.interval
                                                }));
      check(client.pollIntervalMs === originalInterval && client.pollTimer.interval === originalInterval, "original Number/QML int domain");
      config = Object.assign({}, config, {
                               pollIntervalMs: 0
                             });
      phase = "zero";
    } else if (phase === "zero") {
      check(client.pollIntervalMs === 750 && client.pollTimer.interval === 750, "original minimum zero domain");
      config = Object.assign({}, config, {
                               pollIntervalMs: -100
                             });
      phase = "negative";
    } else if (phase === "negative") {
      check(client.pollIntervalMs === 750, "original minimum negative domain");
      priorProbes = count("pidof");
      phase = "polling";
    } else if (phase === "polling" && count("pidof") > priorProbes) {
      alive = false;
      phase = "poll-retired";
    } else if (phase === "poll-retired" && Date.now() - since > 100) {
      check(main._settingsConsumers.size === 2, "only selected poller retired");
      priorProbes = count("pidof");
      second.refresh();
      phase = "common-refresh";
    } else if (phase === "common-refresh" && count("pidof") > priorProbes && main.recording)
      stop();
    else if (phase === "panel") {
      bar.service.runPrimaryAction(Quickshell.screens[0], bar, runtimeApi);
      const button = find(center, item => typeof item.rightClicked === "function" && typeof item.middleClicked === "function");
      check(button, "actual CC button");
      button.clicked();
      check(selectedPanels === 2 && sharedPanels === 0, "originating API opens its own Panel");
      stop();
    } else if (phase === "launch") {
      if (scenario.startsWith("start-"))
        client["toggle" + scenario.slice(6)]();
      else
        client.launchObs();
      phase = "launch-held";
    } else if (phase === "launch-held" && count("pidof") >= 2) {
      check(main.actionBusy && count("obs") === 0, "held probe before launch");
      replacePolicy();
      if (scenario === "launch-retire")
        alive = false;
      mutate({
               "hold-pidof": false
             }, "launched");
    } else if (phase === "launched" && Date.now() - since > 350 && !main.actionBusy) {
      const starts = records("process").filter(row => row.endpoint === "obs");
      if (scenario === "launch-retire")
        check(starts.length === 0, "retired probe cannot launch");
      else if (scenario === "launch-normal")
        check(starts.length === 1 && starts[0].argv.length === 0, "launch keeps admitted normal policy");
      else {
        check(starts.length === 1 && starts[0].argv.includes("--minimize-to-tray"), "automatic output launch");
        check(!main.managedObsLaunch, "managed state captures original false");
      }
      stop();
    } else if (phase === "online") {
      if (scenario === "failure")
        client.toggleRecord();
      else
        client[actions[actionIndex]]();
      phase = "online-done";
    } else if (phase === "online-done" && !main.actionBusy && Date.now() - since > 150) {
      if (scenario === "failure") {
        check(toastRows.length === 1 && toastRows[0].title === "toast.error.title", "failed request reports error");
        stop();
      } else if (++actionIndex === actions.length) {
        check(toastRows.length === 4 && requested("StartRecord") === 1 && requested("StartReplayBuffer") === 1 && requested("StartStream") === 1 && requested("SaveReplayBuffer") === 1, "all online output actions");
        stop();
      } else
        phase = "online";
    } else if (phase === "stop-action") {
      client.toggleRecord();
      phase = "stop-held";
    } else if (phase === "stop-held" && ((scenario === "request-retire" && requested("GetRecordStatus") >= 2) || (scenario === "auto-retire" && requested("GetVirtualCamStatus") === 1) || (scenario === "terminate-retire" && count("pkill") === 1) || (!["auto-retire", "terminate-retire", "request-retire"].includes(scenario) && requested("StopRecord") === 1))) {
      priorToasts = toastRows.length;
      replacePolicy();
      if (scenario.endsWith("retire") && scenario !== "toast-retire" && scenario !== "confirm-retire")
        alive = false;
      const values = {
        "hold-GetRecordStatus": false,
        "hold-StopRecord": false,
        "hold-GetVirtualCamStatus": false,
        "hold-pkill": false
      };
      if (scenario === "confirm-retire")
        values["hold-pidof"] = true;
      mutate(values, scenario === "confirm-retire" ? "confirm-held" : "stopped");
    } else if (phase === "confirm-held" && count("pkill") === 1 && count("pidof") >= 3) {
      alive = false;
      priorToasts = toastRows.length;
      mutate({
               "hold-pidof": false
             }, "stopped");
    } else if (phase === "stopped" && Date.now() - since > 500 && !main.actionBusy) {
      if (scenario === "request-retire")
        check(requested("StopRecord") === 0, "retired request cannot stop output");
      if (scenario === "auto-retire")
        check(count("pkill") === 0, "retired auto-close cannot terminate");
      if (scenario === "terminate-retire")
        check(count("pidof") === 2, "retired terminate cannot start confirmation");
      if (scenario.endsWith("retire") && scenario !== "toast-retire") {
        check(toastRows.length === priorToasts, "retired continuation cannot notify");
        stop();
      } else {
        if (scenario === "auto-close")
          check(!main.managedObsLaunch && count("pkill") === 1 && requested("GetVirtualCamStatus") === 1, "managed stop checks all outputs and confirms termination");
        if (scenario === "auto-active" || scenario === "auto-failure")
          check(main.managedObsLaunch && count("pkill") === 0, "active output or failed snapshot cannot terminate OBS");
        check(heldToast && toastRows.length === 1, "captured output Toast action");
        if (scenario === "toast-retire")
          alive = false;
        heldToast();
        phase = "opened";
      }
    } else if (phase === "opened" && Date.now() - since > 250) {
      const opened = records("process").filter(row => row.endpoint === "obs-open" || row.endpoint === "obs-new-open");
      check(scenario === "toast-retire" ? opened.length === 0 : opened.length === 1 && opened[0].endpoint === "obs-open" && opened[0].argv[0] === base + "/home/captured videos", "Toast retains admitted path/opener and retirement");
      stop();
    } else if (phase === "joined" && Date.now() - since > 250) {
      driver.stop();
      console.log("OBS_LIFETIME: PASS " + scenario);
      Qt.exit(0);
    }
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
}
