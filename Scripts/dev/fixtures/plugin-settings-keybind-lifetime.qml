import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("KBD_ENDPOINT_CASE")
  readonly property string testMode: Quickshell.env("KBD_MODE")
  readonly property string heldStage: Quickshell.env("KBD_HOLD_STAGE")
  property string phase: "start"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var main: null
  property var client: null
  property var panel: null
  property var retained: null
  property bool alive: true
  property var cfg: ({})
  property var descriptor: ({})
  property int scenario: 0
  property int edge: 0
  property var projectionWorker: null
  property var context: selectedContext
  property var sharedContext: pluginContext
  QtObject {
    id: selectedContext
    property var settingsView: root.cfg
    function current() {
      return root.alive;
    }
  }
  QtObject {
    id: pluginContext
    property var settingsView: root.cfg
    function current() {
      return root.alive;
    }
  }
  FileView {
    id: manifest
    path: Quickshell.env("KBD_PLUGIN") + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: endpoints
    path: root.casePath + "/endpoints.jsonl"
    blockLoading: true
  }
  QtObject {
    id: api
    property bool settingsReady: false
    property var settingsContext: root.sharedContext
    property var state: ({
                           cheatsheetData: [
                             {
                               title: "legacy",
                               binds: [
                                 {
                                   keys: "OLD",
                                   desc: "unqualified cache"
                                 }
                               ]
                             }
                           ],
                           detectedCompositor: "niri"
                         })
    property int stateSaves: 0
    function saveState() {
      stateSaves++;
    }
    function tr(key) {
      return key;
    }
  }
  QtObject {
    id: runtimeApi
    property bool settingsReady: root.alive
    property var settingsContext: root.context
    readonly property var settingsView: root.cfg
    property var manifest: root.descriptor
    property var mainInstance: root.main
    property var panelOpenScreen: Quickshell.screens[0]
    function tr(key) {
      return key;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1300
    implicitHeight: 850
    Item {
      id: scene
      width: 1300
      height: 850
    }
  }
  Process {
    id: inspect
    stdout: StdioCollector {
      id: inspection
    }
    onExited: code => {
      try {
        check(code === 0 && inspection.text.includes("KEYBIND_ENDPOINTS_QUIESCENT"), "exact process identities absent before engine exit");
        console.log("KEYBIND_LIFETIME: PASS " + root.testMode + " " + root.heldStage);
        Qt.exit(0);
      } catch (error) {
        root.fail(error);
      }
    }
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("KEYBIND_LIFE_ASSERT: " + testMode + "/" + phase + ": " + label);
    console.log("KEYBIND_LIFE_CHECK: " + label);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function create(name, properties) {
    var component = Qt.createComponent("file://" + Quickshell.env("KBD_PLUGIN") + "/" + name);
    check(component.status === Component.Ready, component.errorString());
    var item = component.createObject(scene, properties);
    check(item, "actual " + name);
    return item;
  }
  function find(object, predicate, visited) {
    visited = visited || new Set();
    if (!object || visited.has(object))
      return null;
    visited.add(object);
    if (predicate(object))
      return object;
    for (var list of [object.data, object.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate, visited);
        if (found)
          return found;
      }
    }
    return null;
  }
  function selectCompositor(name) {
    CompositorService.isNiri = name === "niri";
    CompositorService.isHyprland = name === "hyprland";
    CompositorService.isMango = name === "mango";
    CompositorService.isSway = name === "sway";
    CompositorService.isLabwc = name === "labwc";
  }
  function config(folder, parserMode) {
    var base = casePath + "/" + folder;
    return Object.assign({}, descriptor.metadata.defaultSettings, {
                           niriConfigPath: base + "/niri/main.kdl",
                           hyprlandConfigPath: base + "/hypr/main.conf",
                           hyprlandLuaConfigPath: base + "/hypr/main.lua",
                           mangoConfigPath: base + "/mango/main.conf",
                           hyprlandParserMode: parserMode,
                           modKeyVariable: "$meta",
                           keyLabelMod3: "Hyper",
                           keyColorMod3: "#336699",
                           keyTextMod3: "#c0ffee"
                         });
  }
  readonly property var scenarios: [
    {
      name: "niri",
      mode: "auto",
      descriptions: ["initial niri bind", "included niri bind", "Focus Workspace 1-3"]
    },
    {
      name: "hyprland",
      mode: "conf",
      descriptions: ["initial conf bind", "included conf bind"]
    },
    {
      name: "hyprland",
      mode: "auto",
      descriptions: ["lua bind", ""]
    },
    {
      name: "hyprland",
      mode: "lua",
      descriptions: ["lua bind", ""]
    },
    {
      name: "mango",
      mode: "auto",
      descriptions: ["Run: initial mango bind", "Run: included mango bind", "Focus LEFT", "Close window"]
    },
    {
      name: "sway",
      mode: "auto",
      unsupported: true
    },
    {
      name: "labwc",
      mode: "auto",
      unsupported: true
    },
    {
      name: "unknown",
      mode: "auto",
      unsupported: true
    }
  ]
  function descriptions() {
    var values = [];
    for (var category of client.categories)
      for (var bind of category.binds)
        values.push(bind.desc);
    return values.sort();
  }
  function startScenario() {
    if (main)
      main.destroy();
    var spec = scenarios[scenario];
    selectCompositor(spec.name);
    cfg = config("initial", spec.mode);
    main = create("Main.qml", {
                    pluginApi: api
                  });
    client = main.settingsConsumerFor(context);
    panel = create("Panel.qml", {
                     pluginApi: runtimeApi
                   });
    phase = "functional";
  }
  function heldRows() {
    endpoints.reload();
    endpoints.waitForJob();
    return endpoints.text().trim().split("\n").filter(line => line.length).map(line => JSON.parse(line)).filter(row => row.held);
  }
  function quiesce() {
    if (panel)
      panel.destroy();
    if (main)
      main.destroy();
    phase = "quiesce";
  }
  function inspectNow() {
    inspect.command = ["/usr/bin/python3", "-B", Quickshell.env("KBD_ENDPOINT"), "inspect", casePath + "/endpoints.jsonl"];
    inspect.running = true;
    phase = "inspecting";
  }
  function begin() {
    manifest.waitForJob();
    descriptor = JSON.parse(manifest.text());
    if (testMode === "edges") {
      startEdge();
      return;
    }
    if (testMode === "functional") {
      startScenario();
      return;
    }
    var name = heldStage.startsWith("niri") ? "niri" : heldStage.startsWith("mango") ? "mango" : "hyprland";
    var parserMode = heldStage === "hypr-detect" ? "auto" : heldStage === "hypr-lua" || heldStage === "hyprctl" ? "lua" : "conf";
    if (testMode === "cache" || testMode === "failure" || testMode === "startfail") {
      name = "niri";
      parserMode = "auto";
    }
    selectCompositor(name);
    cfg = config("initial", parserMode);
    main = create("Main.qml", {
                    pluginApi: api
                  });
    client = main.settingsConsumerFor(testMode === "cache" ? sharedContext : context);
    if (testMode !== "cache")
      panel = create("Panel.qml", {
                       pluginApi: runtimeApi
                     });
    phase = testMode === "cache" ? "cache-first" : testMode === "failure" || testMode === "startfail" ? "failure" : "held";
  }
  readonly property var edges: ["empty-niri", "missing-niri", "empty-conf", "missing-conf", "empty-mango", "missing-mango", "auto-conf", "malformed-hyprctl", "split-only"]
  function startEdge() {
    if (panel) {
      panel.destroy();
      panel = null;
    }
    if (main)
      main.destroy();
    var name = edges[edge], compositor = name.includes("mango") ? "mango" : name.includes("conf") || name.includes("hyprctl") ? "hyprland" : "niri";
    selectCompositor(compositor);
    cfg = config("initial", name === "malformed-hyprctl" ? "lua" : name === "auto-conf" ? "auto" : "conf");
    if (name.startsWith("empty") || name.startsWith("missing")) {
      var key = compositor === "niri" ? "niriConfigPath" : compositor === "mango" ? "mangoConfigPath" : "hyprlandConfigPath";
      cfg = Object.assign({}, cfg, {
                            [key]: casePath + "/" + (name.startsWith("empty") ? "empty" : "missing") + (compositor === "niri" ? ".kdl" : ".conf")
                          });
    }
    if (name === "auto-conf")
      cfg = Object.assign({}, cfg, {
                            hyprlandLuaConfigPath: casePath + "/missing.lua"
                          });
    if (name === "split-only")
      cfg = Object.assign({}, cfg, {
                            mergeSequentialBinds: false,
                            splitLargeWorkspaceCategory: false,
                            workspaceSplitThreshold: 2
                          });
    main = create("Main.qml", {
                    pluginApi: api
                  });
    client = main.settingsConsumerFor(context);
    panel = create("Panel.qml", {
                     pluginApi: runtimeApi
                   });
    phase = "edge";
  }
  function nextEdge() {
    edge++;
    if (edge < edges.length)
      startEdge();
    else
      quiesce();
  }
  function drive() {
    if (phase === "start") {
      if (Date.now() - since >= 18000)
        throw new Error("KEYBIND_LIFE_ASSERT: finite Settings startup");
      if (Settings.isLoaded)
        begin();
      return;
    }
    if (Date.now() - since >= 18000)
      throw new Error("KEYBIND_LIFE_ASSERT: finite stage deadline " + phase);
    if (phase === "edge" && client.worker && !client.worker.isCurrentlyParsing) {
      var name = edges[edge];
      if (name === "auto-conf")
        check(JSON.stringify(descriptions()) === JSON.stringify(["initial conf bind", "included conf bind"].sort()), "auto mode falls back to actual conf source");
      else if (name === "split-only") {
        if (!panel.columnItems.some(column => column.some(item => item.desc === "Focus Workspace 1")))
          return;
        check(panel.categories.some(cat => cat.title === "Workspace Navigation"), "unsplit original workspace category");
        projectionWorker = client.worker;
        cfg = Object.assign({}, cfg, {
                              splitLargeWorkspaceCategory: true
                            });
        phase = "split-only";
        return;
      } else
        check(client.categories.length === 0 && panel.rawCategories.length === 0, "empty/missing/malformed source has no previous result: " + name);
      check(api.stateSaves === 0, "edge instance never acquires common cache writer");
      nextEdge();
    } else if (phase === "split-only" && panel.categories.some(cat => cat.title === "panel.workspace-switching")) {
      if (!panel.columnItems.some(column => column.some(item => item.title === "panel.workspace-switching")))
        return;
      check(client.worker === projectionWorker, "split-only rebuilds actual projection without parser replacement");
      cfg = Object.assign({}, cfg, {
                            workspaceSplitThreshold: 10
                          });
      phase = "threshold-high";
    } else if (phase === "threshold-high" && panel.categories.some(cat => cat.title === "Workspace Navigation")) {
      if (!panel.columnItems.some(column => column.some(item => item.title === "Workspace Navigation")))
        return;
      check(client.worker === projectionWorker, "threshold-only restores actual unsplit column");
      cfg = Object.assign({}, cfg, {
                            workspaceSplitThreshold: 1
                          });
      phase = "threshold-low";
    } else if (phase === "threshold-low" && panel.columnItems.some(column => column.some(item => item.title === "panel.workspace-switching"))) {
      check(client.worker === projectionWorker, "threshold-only splits actual column without parser replacement");
      nextEdge();
    } else if (phase === "functional" && client.worker && !client.worker.isCurrentlyParsing) {
      if (!panel.columnItems.some(column => column.some(item => item.type === "bind")))
        return;
      var spec = scenarios[scenario];
      if (spec.unsupported)
        check(client.categories[0].binds[0].keys === spec.name.toUpperCase(), "actual unsupported compositor result");
      else
        check(JSON.stringify(descriptions()) === JSON.stringify(spec.descriptions.slice().sort()), "actual complete compositor bind descriptions " + spec.name + "/" + spec.mode);
      check(api.stateSaves === 0 && api.state.cheatsheetData[0].binds[0].desc === "unqualified cache", "instance result has no shared cache writer");
      check(panel.settingsConsumer === client, "actual Panel uses exact parser client");
      for (var category of client.categories)
        for (var bind of category.binds) {
          check(find(panel, item => item.text === (bind.undescribed ? "panel.no-description" : bind.desc)), "actual compositor description Text");
          for (var token of bind.keys.split(" + ")) {
            var key = find(panel, item => item.text === panel.getKeyLabel(token));
            check(key, "actual compositor key/label Text");
            check(String(key.color).toLowerCase() === String(panel.getKeyTextColor(token)).toLowerCase(), "actual compositor key foreground");
            check(String(key.parent.color).toLowerCase() === String(panel.getKeyColor(token)).toLowerCase(), "actual compositor key badge background");
          }
        }
      panel.destroy();
      panel = null;
      scenario++;
      if (scenario < scenarios.length)
        startScenario();
      else
        quiesce();
    } else if (phase === "held" && heldRows().length) {
      check(heldRows().length === 1, "one held admitted stage");
      retained = client.worker;
      check(main.settingsConsumerFor(context) === client, "multiple renderers share captured client");
      if (testMode === "replace") {
        cfg = config("replacement", cfg.hyprlandParserMode);
        phase = "replaced";
      } else if (testMode === "retire") {
        alive = false;
        phase = "retired";
      } else {
        main.destroy();
        phase = "destroyed";
      }
    } else if (phase === "replaced" && client.worker && !client.worker.isCurrentlyParsing) {
      check(retained === null && client.worker !== retained, "replacement destroys whole old parser generation");
      var values = descriptions().join("|");
      check(heldStage === "hyprctl" ? values.includes("replacement lua bind") : heldStage === "hypr-detect" || heldStage === "hypr-lua" ? values.includes("lua bind") : values.includes("replacement"), "replacement actual selected parser result");
      check(api.stateSaves === 0, "retired stages cannot publish common cache");
      quiesce();
    } else if (phase === "retired" && Date.now() - since > 200) {
      check(!context.current() && client === null && retained === null && !main._settingsConsumers.has(context), "origin retirement destroys client and every stage");
      quiesce();
    } else if (phase === "destroyed" && Date.now() - since > 200) {
      check(main === null && client === null && retained === null, "actual Main destruction owns parser children");
      quiesce();
    } else if (phase === "cache-first" && client.worker && !client.worker.isCurrentlyParsing) {
      check(api.stateSaves === 1 && api.state.cheatsheetSource === client.sourceKey, "sole current plugin-level qualified cache publication");
      var saved = JSON.stringify(client.categories);
      main.destroy();
      main = create("Main.qml", {
                      pluginApi: api
                    });
      client = main.settingsConsumerFor(sharedContext);
      check(client.worker === null && JSON.stringify(client.categories) === saved, "exact source-qualified common cache reused without parser");
      cfg = config("replacement", "auto");
      phase = "cache-replaced";
    } else if (phase === "cache-replaced" && client.worker && !client.worker.isCurrentlyParsing) {
      check(descriptions().join("|").includes("replacement niri bind") && api.stateSaves === 2, "cache identity cannot be attributed to replacement source");
      quiesce();
    } else if (phase === "failure" && client.worker && !client.worker.isCurrentlyParsing) {
      check(client.categories.length === 0, "failed current source does not retain another source result");
      quiesce();
    } else if (phase === "quiesce" && Date.now() - since > 250)
      inspectNow();
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
}
