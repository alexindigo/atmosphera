import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_AUTO_CASE")
  readonly property string scenario: Quickshell.env("PHA_AUTO_SCENARIO")
  readonly property bool osk: ["keyboard", "detect", "backend-detect", "delayed-retire", "private-monitor", "private-retire"].includes(scenario)
  property var main: null
  property var client: null
  property var oldRows: []
  property var oldBackend: null
  property int before: 0
  property int notices: 0
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  QtObject {
    id: sharedApi
    property var manifest: ({
                              metadata: {
                                defaultSettings: {
                                  autoRotateInTabletMode: false,
                                  tabletModeStateFile: root.base + "/state-shared",
                                  backend: "wvkbd",
                                  wvkbdBin: "wvkbd-mobintl"
                                }
                              }
                            })
    property var pluginSettings: manifest.metadata.defaultSettings
    property var settingsContext: sharedContext
    function saveSettings() {
      root.check(false, "explicit-context test cannot claim a native writer");
    }
  }
  QtObject {
    id: selectedApi
    property var pluginSettings: ({
                                    autoRotateInTabletMode: root.scenario === "sensor",
                                    autoRotateOutsideTabletMode: false,
                                    flipVerticalSensorOrientation: true,
                                    syncHyprTouchTransform: true,
                                    showSuccessToast: false,
                                    tabletModeStateFile: root.base + "/state-old",
                                    backend: root.scenario.startsWith("private-") ? "squeekboard" : root.scenario === "backend-detect" ? "auto" : "wvkbd",
                                    wvkbdBin: "wvkbd-old"
                                  })
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
  }
  Process {
    id: joiner
    onExited: code => {
      if (code !== 0)
        root.fail("exact endpoint survived cancellation");
      else
        root.phase = "joined";
    }
  }
  Process {
    id: peer
    command: ["/usr/bin/python3", root.base + "/peer.py"]
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices++;
    }
  }
  Item {
    id: content
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("AUTOMATIC_LIFETIME_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function match(name, predicate) {
    return rows().filter(row => row.endpoint === name && (!predicate || predicate(row)));
  }
  function patch(values) {
    selectedApi.pluginSettings = Object.assign({}, selectedApi.pluginSettings, values);
  }
  function releaseTag(tag) {
    release.command = ["touch", base + "/release-" + tag];
    release.running = true;
  }
  function join(items) {
    oldRows = items;
    phase = "joining";
    joiner.command = ["python3", "-c",
                      "import json,sys,time;from pathlib import Path\nr=json.loads(sys.argv[1]);end=time.monotonic()+5\ndef live(x):\n p=Path('/proc')/str(x['pid'])/'stat'\n try:return p.read_text().split(') ',1)[1].split()[19]==x['start']\n except FileNotFoundError:return False\nwhile any(live(x) for x in r):\n if time.monotonic()>end:raise SystemExit(1)\n time.sleep(.02)",
                      JSON.stringify(items)];
    joiner.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    const component = Qt.createComponent("file://" + base + "/plugin/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: sharedApi
                                  });
    check(main, "actual Main constructs");
    phase = "initial";
  }
  function pass() {
    driver.stop();
    console.log("AUTOMATIC_LIFETIME: PASS " + scenario);
    Qt.exit(0);
  }
  function drive() {
    if (phase === "begin")
      return;
    check(Date.now() - since < 18000, "finite lifetime phase");
    if (phase === "initial") {
      if (Date.now() - since < 400 || (!osk && main.compositorBackend === "unknown"))
        return;
      check(main.activatePolicy(selectedContext), "admit selected runtime policy");
      if (osk) {
        if (scenario !== "backend-detect") {
          client = main.settingsConsumerFor(selectedContext);
          check(client === main.settingsConsumerFor(selectedContext), "two renderers share one availability client");
          main.settingsConsumerFor(sharedContext);
          check(main.policyContext === selectedContext, "inactive view cannot select keyboard policy");
        }
        phase = "osk-ready";
      } else if (["apply", "touch", "retire-apply", "retire-touch"].includes(scenario)) {
        main.compositorBackend = "hyprland";
        main.hyprMonitorStateByOutput = {
          "eDP-test": {
            name: "eDP-test",
            width: 1280,
            height: 720,
            scale: 1
          }
        };
        main.cycleTransform("eDP-test", selectedContext);
        phase = "held";
      } else if (scenario === "sensor")
        phase = "sensor-ready";
      else if (["exit-restore", "restore-retry"].includes(scenario)) {
        patch({
                autoRotateOutsideTabletMode: true
              });
        main._setTransform("eDP-test", "180");
        main._beginAutoRotateSession("eDP-test", main.capturePolicy(selectedContext));
        if (scenario === "restore-retry")
          main.compositorBackend = "unsupported";
        patch({
                autoRotateOutsideTabletMode: false
              });
        main._endAutoRotateSession();
        main._syncAutoRotateLifecycle();
        phase = "restore";
      } else if (scenario === "state-file")
        phase = "state-held";
    } else if (phase === "sensor-ready") {
      if (!match("monitor-sensor").length)
        return;
      releaseTag("sensor");
      phase = "sensor-result";
    } else if (phase === "sensor-result") {
      if (!match("niri", row => row.argv.includes("270")).length || main.isBusy("eDP-test"))
        return;
      check(main.transformForOutput("eDP-test") === "270", "actual sensor line reaches selected flip transform");
      selectedContext.alive = false;
      join(match("monitor-sensor"));
    } else if (phase === "held") {
      const held = scenario.includes("touch") ? match("hyprctl", row => row.argv.join(" ") === "-j devices") : match("hyprctl", row => row.argv[1] === "monitor");
      if (!held.length)
        return;
      before = rows().length;
      if (scenario.startsWith("retire"))
        selectedContext.alive = false;
      else
        patch({
                syncHyprTouchTransform: false,
                showSuccessToast: true
              });
      releaseTag(scenario.includes("touch") ? "touch" : "apply");
      phase = "held-result";
    } else if (phase === "held-result" && Date.now() - since > 700) {
      const effects = rows().slice(before).filter(row => row.endpoint === "hyprctl" && row.argv[0] === "keyword" && row.argv[1].startsWith("device["));
      if (scenario === "retire-touch")
        check(effects.length === 0, "retired touch query cannot dispatch");
      else if (scenario === "retire-apply")
        check(!match("hyprctl", row => row.argv.join(" ") === "-j devices").length && notices === 0, "retired apply cannot start touch or notification");
      else
        check(effects.length === 2 && notices === 0, "captured apply keeps touch and notification policy");
      pass();
    } else if (phase === "restore") {
      if (scenario === "restore-retry" && main.compositorBackend === "unsupported") {
        check(main._autoRotateRestoreOutputName === "eDP-test", "failed admission retains restore Retry");
        main.compositorBackend = "niri";
        main._syncAutoRotateLifecycle();
        phase = "restore-result";
      } else
        phase = "restore-result";
    } else if (phase === "restore-result" && Date.now() - since > 700) {
      check(match("niri", row => row.argv.includes("transform") && row.argv.includes("180")).length >= 1, "session exit retains admitted restore transform");
      pass();
    } else if (phase === "state-held") {
      const held = match("sh", row => row.argv[row.argv.length - 1] === base + "/state-old");
      if (held.length < 2)
        return;
      patch({
              tabletModeStateFile: base + "/state-new"
            });
      join(held);
    } else if (phase === "joined" && Date.now() - since > 300) {
      if (scenario === "state-file") {
        check(match("sh", row => row.argv[row.argv.length - 1] === base + "/state-new").length >= 2, "replacement state watcher and read start after old identities stop");
        check(!main._tabletModeDetected, "obsolete state cannot publish");
      } else if (scenario === "sensor")
        check(!main._autoRotatePendingTransform, "retired sensor cannot enqueue transform");
      else if (scenario.startsWith("private-")) {
        check(!main._backend && main.resolvedBackend === "", "retired physical monitor owner removed");
        peer.running = false;
      } else if (scenario === "detect" || scenario === "backend-detect")
        check(main._backend?.wvkbdBin === "wvkbd-new", "held old availability cannot choose replacement binary");
      else if (scenario === "delayed-retire")
        check(!rows().some(row => row.event === "signal" && row.endpoint === "wvkbd-old"), "retired keyboard cannot signal");
      pass();
    } else if (phase === "osk-ready") {
      if (scenario === "backend-detect") {
        const held = match("busctl");
        if (!held.length)
          return;
        patch({
                backend: "wvkbd",
                wvkbdBin: "wvkbd-new"
              });
        join(held);
      } else if (scenario === "detect") {
        const held = match("which", row => row.argv[0] === "wvkbd-old");
        if (!held.length)
          return;
        patch({
                wvkbdBin: "wvkbd-new"
              });
        join(held);
      } else if (scenario.startsWith("private-")) {
        if (!match("dbus-monitor").length || !client.gsettingsOk)
          return;
        check(!client.available, "private service initially absent");
        peer.running = true;
        phase = "bus-owned";
      } else {
        const launches = match("wvkbd-old", row => !row.event);
        if (!main.available || !launches.length)
          return;
        main.toggleKeyboard(selectedContext);
        if (scenario === "delayed-retire") {
          selectedContext.alive = false;
          join(launches);
        } else
          phase = "shown";
      }
    } else if (phase === "shown") {
      const signals = match("wvkbd-old", row => row.event === "signal");
      if (!signals.length)
        return;
      check(signals[0].at - match("wvkbd-old", row => !row.event)[0].at >= 0.24, "actual keyboard respects startup show boundary");
      oldRows = match("wvkbd-old");
      patch({
              wvkbdBin: "wvkbd-new"
            });
      phase = "replaced";
    } else if (phase === "replaced") {
      if (!main.available || main._backend?.wvkbdBin !== "wvkbd-new")
        return;
      main.toggleKeyboard(selectedContext);
      phase = "new-shown";
    } else if (phase === "new-shown") {
      if (!match("wvkbd-new", row => row.event === "signal").length)
        return;
      selectedContext.alive = false;
      join(oldRows.concat(match("wvkbd-new")));
    } else if (phase === "bus-owned" && client.available) {
      check(main.available && client.activePolicy, "actual private NameOwnerChanged reaches every active view");
      if (scenario === "private-retire") {
        selectedContext.alive = false;
        join(match("dbus-monitor").concat(match("dconf")));
      } else {
        peer.running = false;
        phase = "bus-lost";
      }
    } else if (phase === "bus-lost" && !client.available) {
      oldRows = match("dbus-monitor").concat(match("dconf"));
      patch({
              backend: "wvkbd",
              wvkbdBin: "wvkbd-new"
            });
      phase = "bus-replaced";
    } else if (phase === "bus-replaced") {
      if (!main.available || main.resolvedBackend !== "wvkbd")
        return;
      selectedContext.alive = false;
      join(oldRows.concat(match("wvkbd-new")));
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
    interval: 10
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
