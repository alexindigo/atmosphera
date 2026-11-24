import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_OUTPUT_CASE")
  readonly property string scenario: Quickshell.env("PHA_OUTPUT_SCENARIO")
  readonly property bool parserCase: scenario === "parser"
  property var main: null
  property var panel: null
  property var oldRows: []
  property var beforeOutputs: []
  property int fetchesBefore: 0
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  QtObject {
    id: sharedApi
    property var manifest: ({
                              metadata: {
                                defaultSettings: {
                                  niriConfigPath: root.base + "/Shared.kdl",
                                  backend: "sway",
                                  swayCommand: root.base + "/bin/shared-output",
                                  hyprctlCommand: root.base + "/bin/shared-output",
                                  gridSize: 40,
                                  snapToGrid: true
                                }
                              }
                            })
    property var pluginSettings: manifest.metadata.defaultSettings
    property var settingsContext: sharedContext
    property var mainInstance: root.main
    function tr(key, values) {
      return key;
    }
  }
  QtObject {
    id: selectedApi
    property var manifest: sharedApi.manifest
    property var pluginSettings: ({
                                    niriConfigPath: root.base + "/Selected.kdl",
                                    backend: "hyprland",
                                    swayCommand: root.base + "/bin/selected-output",
                                    hyprctlCommand: root.base + "/bin/selected-output",
                                    gridSize: 25,
                                    snapToGrid: true
                                  })
    property var settingsContext: selectedContext
    property var mainInstance: root.main
    function tr(key, values) {
      return key;
    }
  }
  QtObject {
    id: sharedContext
    readonly property var settingsView: sharedApi.pluginSettings
    function current() {
      return true;
    }
  }
  QtObject {
    id: selectedContext
    property bool alive: true
    readonly property var settingsView: selectedApi.pluginSettings
    function current() {
      return alive;
    }
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: release
    onExited: code => {
      if (code !== 0)
        root.fail("barrier release failed");
    }
  }
  Process {
    id: quiescence
    onExited: code => {
      if (code !== 0)
        root.fail("held query survived cancellation");
      else
        root.phase = root.phase === "source-joined" ? "source-readback" : "retired-readback";
    }
  }
  Item {
    id: content
    width: 1400
    height: 900
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OUTPUT_LIFETIME_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function create(name, api) {
    const component = Qt.createComponent("file://" + base + "/plugin/" + name + ".qml");
    check(component.status === Component.Ready, component.errorString());
    const item = component.createObject(content, {
                                          pluginApi: api
                                        });
    check(item, "actual " + name);
    return item;
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function fetchRows() {
    return rows().filter(row => row.endpoint.endsWith("-output") && (row.argv[0] === "monitors" || row.argv[0] === "-t"));
  }
  function selectedFetches() {
    return fetchRows().filter(row => row.endpoint === "selected-output");
  }
  function releaseTag(tag) {
    release.command = ["touch", base + "/release-" + tag];
    release.running = true;
  }
  function join(rowsToJoin, next) {
    phase = next;
    quiescence.command = ["python3", "-c",
                          "import json,sys,time; from pathlib import Path; rows=json.loads(sys.argv[1]); end=time.monotonic()+5\ndef live(r):\n p=Path('/proc')/str(r['pid'])/'stat'; return p.exists() and p.read_text().split(') ',1)[1].split()[19]==r['start']\nwhile any(live(r) for r in rows):\n if time.monotonic()>end: raise SystemExit(1)\n time.sleep(.02)",
                          JSON.stringify(rowsToJoin)];
    quiescence.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    main = create("Main", sharedApi);
    panel = create("Panel", selectedApi);
    phase = "initial";
  }
  function pass() {
    console.log("OUTPUT_LIFETIME: PASS " + scenario);
    Qt.exit(0);
  }
  function drive() {
    if (phase === "begin")
      return;
    check(Date.now() - since < 18000, "finite held output phase");
    if (parserCase) {
      if (phase === "initial") {
        const held = rows().filter(row => row.endpoint === "cat" && row.argv[0] === base + "/Selected.kdl");
        if (!held.length)
          return;
        oldRows = held;
        selectedApi.pluginSettings = Object.assign({}, selectedApi.pluginSettings, {
                                                     niriConfigPath: base + "/Replacement.kdl"
                                                   });
        join(oldRows, "source-joined");
      } else if (phase === "source-readback") {
        if (panel.loading)
          return;
        check(panel.niriOutputs.length === 1 && panel.niriOutputs[0].name === "Replacement", "replacement parser result excludes held old source");
        check(!rows().some(row => row.endpoint === "cat" && row.argv[0] === base + "/Foreign.kdl"), "obsolete source cannot start queued include");
        selectedApi.pluginSettings = Object.assign({}, selectedApi.pluginSettings, {
                                                     niriConfigPath: base + "/Retired.kdl"
                                                   });
        phase = "retiring";
      } else if (phase === "retiring") {
        const held = rows().filter(row => row.endpoint === "cat" && row.argv[0] === base + "/Retired.kdl");
        if (!held.length)
          return;
        selectedContext.alive = false;
        join(held, "retired-joined");
      } else if (phase === "retired-readback") {
        check(!main.configClients.has(selectedContext) && panel.niriOutputs.length === 0, "retired parser/client removed without replacing shared owner");
        check(main.niriOutputs.length === 1 && main.niriOutputs[0].name === "Shared", "shared parser unaffected");
        check(!rows().some(row => row.endpoint === "cat" && row.argv[0] === base + "/RetiredChild.kdl"), "retired parser cannot start queued include");
        pass();
      }
      return;
    }
    if (phase === "initial") {
      if (main.isRefreshing || Date.now() - since < 300)
        return;
      beforeOutputs = JSON.parse(JSON.stringify(main.draftOutputs));
      main.refreshOutputs(selectedContext);
      phase = "fetching";
    } else if (phase === "fetching") {
      if (scenario.includes("fetch")) {
        const held = selectedFetches();
        if (!held.length)
          return;
        if (scenario === "retire-fetch") {
          selectedContext.alive = false;
          join(held, "retired-joined");
        } else {
          selectedApi.pluginSettings = Object.assign({}, selectedApi.pluginSettings, {
                                                       backend: "sway"
                                                     });
          releaseTag("fetch");
          phase = "fetch-result";
        }
      } else {
        if (main.isRefreshing || main.draftOutputs[0]?.name !== "Selected")
          return;
        main.applyLayout(selectedContext);
        phase = "applying";
      }
    } else if (phase === "fetch-result" && !main.isRefreshing) {
      check(main.draftOutputs[0]?.width === 1280 && main.draftOutputs[0]?.refresh === 59.94, "held fetch parses with captured Hyprland backend after selected backend changes");
      pass();
    } else if (phase === "retired-readback") {
      check(!main.isRefreshing && JSON.stringify(main.draftOutputs) === JSON.stringify(beforeOutputs), "retired fetch cannot publish layout");
      pass();
    } else if (phase === "applying") {
      const held = rows().filter(row => row.endpoint === "selected-output" && row.argv[0] === "keyword");
      if (!held.length)
        return;
      fetchesBefore = fetchRows().length;
      if (scenario === "retire-apply")
        selectedContext.alive = false;
      else
        selectedApi.pluginSettings = Object.assign({}, selectedApi.pluginSettings, {
                                                     backend: "sway",
                                                     hyprctlCommand: base + "/bin/shared-output"
                                                   });
      releaseTag("apply");
      phase = "apply-result";
    } else if (phase === "apply-result" && !main.isApplying && !main.isRefreshing && Date.now() - since > 300) {
      const after = fetchRows().slice(fetchesBefore);
      if (scenario === "retire-apply")
        check(after.length === 0, "retired admitted apply cannot start completion refresh");
      else
        check(after.length === 1 && after[0].endpoint === "selected-output" && after[0].argv.join(" ") === "monitors -j" && main.draftOutputs[0]?.width === 1280, "apply completion retains originating backend and command policy");
      pass();
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
