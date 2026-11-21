// Focused G2 capture admission characterization. Not native/page acceptance.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_CAPTURE_PLUGIN")
  readonly property string base: Quickshell.env("PHA_CAPTURE_CASE")
  readonly property bool original: Quickshell.env("PHA_CAPTURE_ORIGINAL") === "1"
  readonly property bool completion: Quickshell.env("PHA_CAPTURE_COMPLETION") === "1"
  readonly property bool retiredSelector: Quickshell.env("PHA_CAPTURE_RETIRED_SELECTOR") === "1"
  readonly property bool retiredPreflight: Quickshell.env("PHA_CAPTURE_RETIRED_PREFLIGHT") === "1"
  property var callbacks: []
  property string firstOutput: ""
  property int savedCount: 0
  property double retiredSince: 0
  property var main: null
  property var selected: null
  property var api: null
  property var policy: null
  property bool started: false
  property bool current: true
  property string phase: "startup"
  property double since: Date.now()
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
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      if (title === "messages.saved" || title === "messages.replay-saved") {
        root.callbacks = root.callbacks.concat([
                                                 {
                                                   path: description,
                                                   callback: actionCallback
                                                 }
                                               ]);
        ++root.savedCount;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CAPTURE_RUNTIME_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    if (object?.item) {
      const loaded = find(object.item, predicate);
      if (loaded)
        return loaded;
    }
    if (typeof object?.objectAt === "function" && typeof object.count === "number") {
      for (var index = 0; index < object.count; ++index) {
        const instance = find(object.objectAt(index), predicate);
        if (instance)
          return instance;
      }
    }
    for (const list of [object?.data, object?.children, object?.instances]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (const child of list) {
        const result = find(child, predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function makeApi(settings, selected) {
    const context = {
      current: function () {
        return !selected || root.current;
      }
    };
    Object.defineProperty(context, "settingsView", {
                            get: function () {
                              return Object.freeze(Object.assign({}, settings));
                            }
                          });
    Object.freeze(context);
    return {
      pluginDir: base + "/plugin",
      manifest: JSON.parse(manifest.text()),
      pluginSettings: settings,
      settingsContext: context,
      tr: function (key) {
        return key;
      },
      saveSettings: function () {
        return true;
      },
      withCurrentScreen: function (callback) {
        callback(Quickshell.screens[0]);
      },
      openPanel: function () {},
      closePanel: function () {},
      mainInstance: null
    };
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    const shared = {
      directory: base + "/shared",
      recordingSavePath: base + "/shared",
      screenshotPath: base + "/shared",
      videoPath: base + "/shared",
      audioSource: "none",
      videoSource: "portal",
      frameRate: "13",
      replayEnabled: true,
      recordingNotifications: false
    };
    const values = Object.assign({}, shared, {
                                   directory: base + "/selected",
                                   recordingSavePath: base + "/selected",
                                   screenshotPath: base + "/selected",
                                   videoPath: base + "/selected",
                                   frameRate: "29",
                                   recordingNotifications: true
                                 });
    if (completion)
      values.copyToClipboard = true;
    api = makeApi(shared, false);
    selected = makeApi(values, true);
    const component = Qt.createComponent("file://" + base + "/plugin/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: api
                                  });
    check(main, "actual Main constructs");
    api.mainInstance = main;
    selected.mainInstance = main;
    phase = "ready";
  }
  function drive() {
    check(Date.now() - since < 15000, "finite phase deadline");
    if (phase === "ready") {
      if (plugin === "screen-recorder") {
        if (!main.isAvailable)
          return;
        main.startRecording(selected.settingsContext);
        phase = "record-admitted";
      } else if (plugin === "screen-shot-and-record") {
        main.open("record", selected.settingsContext);
        phase = retiredPreflight ? "preflight-retire" : "selector";
      } else {
        main.runMeasure(selected);
        phase = "measure";
      }
    } else if (phase === "record-admitted") {
      if (!original)
        check(main.recordingPolicy?.settings.directory === base + "/selected", "recording retains selected admission");
      selected.pluginSettings.directory = base + "/changed";
      if (completion)
        selected.pluginSettings.copyToClipboard = false;
      api.pluginSettings.directory = base + "/changed-shared";
      gate.command = ["rm", base + "/hold-portal"];
      gate.running = true;
      phase = "record-wait";
    } else if (phase === "record-wait") {
      if (!main.isRecording)
        return;
      const observed = rows().find(row => row.endpoint === "gpu-screen-recorder");
      check(observed && observed.argv.includes("29"), "selected frame rate reaches inert recorder");
      const output = observed.argv[observed.argv.indexOf("-o") + 1];
      firstOutput = output;
      check(output.startsWith(base + "/selected/"), "selected output directory reaches inert recorder");
      policy = main.recordingPolicy;
      gate.command = ["touch", base + "/release-recorder"];
      gate.running = true;
      phase = "record-complete";
    } else if (phase === "record-complete" && !main.isRecording && !main.isPending && !gate.running) {
      if (completion) {
        if (!rows().find(row => row.endpoint === "wl-copy"))
          return;
        check(savedCount === 1 && callbacks[0].path === firstOutput, "held recorder completion retains original toast destination");
        check(rows().find(row => row.endpoint === "wl-copy").stdin === "file://" + firstOutput, "held recorder completion retains clipboard policy");
        main.startRecording(selected.settingsContext);
        phase = "record-again";
      } else {
        main.startReplay(selected.settingsContext);
        phase = "replay";
      }
    } else if (phase === "record-again" && rows().filter(row => row.endpoint === "gpu-screen-recorder").length === 2 && !main.isPending) {
      check(main.outputPath !== firstOutput, "later recorder replaces only its own output");
      callbacks[0].callback();
      phase = "delayed-open";
    } else if (phase === "delayed-open") {
      const opened = rows().find(row => row.endpoint === "xdg-open");
      if (!opened)
        return;
      check(opened.argv[0] === firstOutput, "delayed toast opens the completed recording, not the next output");
      selected.pluginSettings.copyToClipboard = true;
      main.startReplay(selected.settingsContext);
      selected.pluginSettings.copyToClipboard = false;
      phase = "replay";
    } else if (phase === "replay") {
      if (!main.isReplaying)
        return;
      check(main.replayPolicy?.settings.directory === base + "/changed", "independent replay captures the next selected context view");
      const observed = rows().filter(row => row.endpoint === "gpu-screen-recorder");
      const replay = observed[observed.length - 1];
      check(observed.length === (completion ? 3 : 2) && replay.argv.includes("-r"), "actual replay command reaches inert recorder");
      check(replay.argv[replay.argv.indexOf("-o") + 1] === base + "/changed/", "next replay uses its own newly admitted directory");
      if (!completion)
        current = false;
      gate.command = ["touch", base + (completion ? "/emit-replay-1" : "/release-replay")];
      gate.running = true;
      phase = completion ? "replay-result" : "retire";
    } else if (phase === "replay-result" && !gate.running) {
      if (savedCount !== 2 || rows().filter(row => row.endpoint === "wl-copy").length !== 2)
        return;
      check(callbacks[1].path === base + "/controlled-replay-1.mp4", "actual replay stdout reaches retained toast");
      check(rows().filter(row => row.endpoint === "wl-copy")[1].stdin === "file://" + base + "/controlled-replay-1.mp4", "replay completion retains its captured clipboard setting");
      current = false;
      gate.command = ["touch", base + "/emit-replay-2"];
      gate.running = true;
      retiredSince = Date.now();
      phase = "late-replay";
    } else if (phase === "late-replay" && !gate.running && Date.now() - retiredSince > 300) {
      check(savedCount === 2 && rows().filter(row => row.endpoint === "wl-copy").length === 2, "retired replay stdout cannot publish completion effects");
      callbacks[0].callback();
      callbacks[1].callback();
      gate.command = ["touch", base + "/release-replay"];
      gate.running = true;
      phase = "retire";
    } else if (phase === "preflight-retire") {
      check(main.recordingCheckTarget === "record", "recording preflight admitted before retirement");
      current = false;
      gate.command = ["rm", base + "/hold-pidof"];
      gate.running = true;
      retiredSince = Date.now();
      phase = "selector-retired";
    } else if (phase === "selector-retired" && !gate.running && Date.now() - retiredSince > 350) {
      check(!main.active && !rows().some(row => row.endpoint === "record.sh"), "retired preflight/selector cannot start a capture stage");
      phase = "retire";
    } else if (phase === "selector" && main.active) {
      const selector = find(main, item => typeof item.finish === "function");
      if (!selector)
        return;
      if (!original)
        check(selector.actionPolicy.settings.recordingSavePath === base + "/selected", "selector receives admitted selected policy");
      selected.pluginSettings.recordingSavePath = base + "/changed";
      selector.dragStartX = 1;
      selector.dragStartY = 1;
      selector.draggingX = 21;
      selector.draggingY = 21;
      selector.mouseButton = Qt.LeftButton;
      if (retiredSelector)
        current = false;
      selector.finish();
      retiredSince = Date.now();
      phase = retiredSelector ? "selector-retired" : "selector-command";
    } else if (phase === "selector-command") {
      const observed = rows().find(row => row.endpoint === "record.sh");
      if (!observed)
        return;
      check(observed.argv[observed.argv.indexOf("--dir") + 1] === base + "/selected", "selected recording folder reaches actual inert helper");
      check(observed.argv.includes("--notify"), "selected notification policy reaches actual inert helper");
      current = false;
      phase = "retire";
    } else if (phase === "measure") {
      const measure = find(main, item => typeof item.show === "function" && item.isVisible === true);
      if (!measure)
        return;
      const window = find(measure, item => typeof item.doScreenshot === "function");
      if (!window)
        return;
      if (!original)
        check(measure.actionPolicy.settings.screenshotPath === base + "/selected", "retained measure overlay has originating policy");
      selected.pluginSettings.screenshotPath = base + "/changed";
      window.doScreenshot({
                            x1: 10,
                            y1: 10,
                            x2: 30,
                            y2: 30
                          }, "#ffffff");
      phase = "measure-command";
    } else if (phase === "measure-command") {
      const observed = rows().find(row => row.endpoint === "measure.sh");
      if (!observed)
        return;
      check(observed.argv[observed.argv.length - 2] === base + "/selected", "retained selected path reaches actual inert measure helper");
      current = false;
      phase = "retire";
    } else if (phase === "retire" && !gate.running) {
      check(main.capturePolicy(selected.settingsContext) === null, "retired origin cannot admit a later stage");
      if (plugin === "screen-recorder" && (main.isReplaying || main.isReplayPending))
        return;
      if (completion)
        check(rows().filter(row => row.endpoint === "xdg-open").length === 1, "retired delayed Toast callbacks cannot open files");
      console.log("CAPTURE_RUNTIME: PASS " + plugin);
      Qt.exit(0);
    }
  }
  Item {
    id: content
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error) + "\n" + error.stack);
        Qt.exit(2);
      }
    }
  }
  Component.onCompleted: begin()
}
