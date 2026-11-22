// Individual retained Toolkit overlays. Every physical/upload helper is inert.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_CAPTURE_CASE")
  readonly property string scenario: Quickshell.env("PHA_CAPTURE_LIFETIME")
  property var main: null
  property var api: null
  property var selected: null
  property var sibling: null
  property var overlay: null
  property var window: null
  property var policy: null
  property bool current: true
  property bool started: false
  property bool holdScreen: false
  property var screenCallbacks: []
  property int mirrorNotices: 0
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
      if (title === "mirror.screenshotSaved" || title === "mirror.recordSaved")
        ++root.mirrorNotices;
    }
  }
  Item {
    id: content
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CAPTURE_OVERLAY_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    if (object?.item) {
      const value = find(object.item, predicate);
      if (value)
        return value;
    }
    for (const list of [object?.data, object?.children, object?.instances]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (const child of list) {
        const value = find(child, predicate);
        if (value)
          return value;
      }
    }
    return null;
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function makeApi(settings, chosen) {
    const context = {
      current: function () {
        return !chosen || root.current;
      }
    };
    Object.defineProperty(context, "settingsView", {
                            get: function () {
                              return Object.freeze(Object.assign({}, settings));
                            }
                          });
    return {
      pluginDir: base + "/plugin",
      manifest: JSON.parse(manifest.text()),
      pluginSettings: settings,
      settingsContext: Object.freeze(context),
      tr: function (key) {
        return key;
      },
      saveSettings: function () {},
      withCurrentScreen: function (callback) {
        if (root.holdScreen)
          root.screenCallbacks = root.screenCallbacks.concat([callback]);
        else
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
    api = makeApi({
                    screenshotPath: base + "/shared",
                    videoPath: base + "/shared"
                  }, false);
    selected = makeApi({
                         screenshotPath: base + "/selected",
                         videoPath: base + "/selected",
                         filenameFormat: "captured",
                         recordSkipConfirmation: true,
                         recordCopyToClipboard: true,
                         gifMaxSeconds: 30,
                         x02ApiKey: "synthetic-selected",
                         x02Expiry: "1d",
                         shareSkipPopover: true
                       }, true);
    sibling = makeApi({
                        screenshotPath: base + "/sibling",
                        videoPath: base + "/sibling"
                      }, false);
    const component = Qt.createComponent("file://" + base + "/plugin/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: api
                                  });
    check(main, "actual Main constructs");
    api.mainInstance = main;
    selected.mainInstance = main;
    sibling.mainInstance = main;
    phase = "ready";
  }
  function drive() {
    check(Date.now() - since < 16000, "finite overlay deadline");
    if (phase === "ready") {
      policy = main.captureAction(selected);
      if (scenario === "measure-replacement") {
        main.runMeasure(selected);
        overlay = find(main, item => typeof item.show === "function" && item.mainInstance === main && item.actionPolicy?.api === selected);
        check(overlay, "actual selected measure overlay");
        window = find(overlay, item => typeof item.doScreenshot === "function");
        check(window, "actual measure window");
        window.doScreenshot({
                              x1: 10,
                              y1: 10,
                              x2: 30,
                              y2: 30
                            }, "#ffffff");
        main.runMeasure(sibling);
        phase = "measure";
      } else if (scenario === "annotate-zoom") {
        overlay = find(main, item => typeof item.parseAndShow === "function");
        overlay.parseAndShow("0,0 32x32", base + "/synthetic.png", Quickshell.screens[0], policy);
        window = find(overlay, item => typeof item.requestZoom === "function");
        check(window, "actual annotation window");
        overlay.zoomScale = 2;
        window.requestZoom(1);
        check(overlay.zoomScale === 1 && overlay.actionPolicy === policy, "annotation zoom restore retains its admitted policy");
        phase = "finish";
      } else if (scenario === "annotate-share" || scenario === "annotate-save") {
        overlay = find(main, item => typeof item.parseAndShow === "function");
        overlay.parseAndShow("0,0 32x32", base + "/synthetic.png", Quickshell.screens[0], policy);
        window = find(overlay, item => typeof item.flattenAndShare === "function");
        overlay.zoomScale = 2;
        if (scenario === "annotate-share")
          window.flattenAndShare();
        else
          window.flattenAndSave();
        selected.pluginSettings.x02ApiKey = "changed";
        selected.pluginSettings.x02Expiry = "30d";
        selected.pluginSettings.screenshotPath = base + "/changed";
        main.runMeasure(sibling);
        phase = scenario === "annotate-share" ? "share" : "save";
      } else if (scenario === "mirror") {
        main.runMirror(selected);
        overlay = find(main, item => typeof item._doScreenshot === "function");
        check(overlay.actionPolicy.api === selected, "mirror retains opening policy");
        overlay._imgCapture = {
          captureToFile: function (path) {}
        };
        overlay._recorder = {
          outputLocation: "",
          record: function () {},
          stop: function () {}
        };
        overlay._pinOnShot = false;
        overlay._doScreenshot();
        selected.pluginSettings.screenshotPath = base + "/changed";
        main.runMeasure(sibling);
        overlay._onImageCaptured(base + "/synthetic.png");
        overlay._doStartRecord();
        selected.pluginSettings.videoPath = base + "/changed";
        overlay._doStopRecord();
        overlay._doSaveRecord();
        current = false;
        phase = "mirror";
      } else {
        holdScreen = true;
        main.runRecordFullscreen("gif", false, false, false, selected);
        main.runRecordFullscreen("mp4", true, true, true, sibling);
        check(screenCallbacks.length === 1 && main.pendingRecordFormat === "gif", "screen admission cannot be overwritten before its callback");
        holdScreen = false;
        screenCallbacks[0](Quickshell.screens[0]);
        phase = "record-start";
      }
    } else if (phase === "measure") {
      const row = rows().find(row => row.endpoint === "measure.sh");
      if (!row)
        return;
      check(row.argv[row.argv.length - 2] === base + "/selected", "held measure cannot borrow replacement policy");
      phase = "finish";
    } else if (phase === "share") {
      const row = rows().find(row => row.endpoint === "share-upload.sh");
      if (!row)
        return;
      check(row.argv[1] === "synthetic-selected" && row.argv[2] === "1d", "actual upload receives retained key and expiry");
      if (window.isUploading)
        return;
      check(window.shareUrl === "https://controlled.invalid/capture" && !window.showSharePopover, "retained share popover and clipboard policy");
      phase = "finish";
    } else if (phase === "save") {
      const row = rows().find(row => row.endpoint === "annotate.sh");
      if (!row)
        return;
      check(row.argv[0] === "save" && row.argv[2].startsWith(base + "/selected/"), "actual annotation save retains selected destination");
      if (window.isSaving)
        return;
      phase = "finish";
    } else if (phase === "mirror") {
      const shot = rows().find(row => row.endpoint === "mirror-screenshot.sh"), record = rows().find(row => row.endpoint === "mirror-record.sh");
      if (!shot || !record)
        return;
      check(shot.argv[1] === base + "/selected" && record.argv[1] === base + "/selected", "mirror shot and record retain independent selected destinations");
      if (Date.now() - since < 350 || overlay._isSaving)
        return;
      check(mirrorNotices === 0, "retired mirror completions do not announce selected results");
      overlay.hide();
      current = false;
      check(overlay._doSaveRecord() === false, "retired mirror cannot launch saved record stage");
      phase = "finish";
    } else if (phase === "record-start") {
      const row = rows().find(row => row.endpoint === "wl-screenrec");
      if (!row)
        return;
      overlay = find(main, item => typeof item._saveToFile === "function");
      check(overlay.isRecording && overlay.actionPolicy.api === selected, "actual record overlay retains originating API");
      selected.pluginSettings.videoPath = base + "/changed";
      selected.pluginSettings.recordCopyToClipboard = false;
      if (scenario === "record-retirement")
        current = false;
      main.runMeasure(sibling);
      gate.command = ["touch", base + "/release-recorder"];
      gate.running = true;
      phase = "record-complete";
    } else if (phase === "record-complete") {
      if (scenario === "record-retirement") {
        if (overlay.recordState !== "")
          return;
        if (Date.now() - since < 350)
          return;
        check(!rows().some(row => row.endpoint === "record.sh" || row.endpoint === "wl-copy"), "retired recorder cannot convert, save or copy");
        phase = "finish";
        return;
      }
      const copy = rows().find(row => row.endpoint === "wl-copy");
      if (!copy)
        return;
      check(copy.stdin.includes(base + "/selected/"), "record conversion and save retain selected clipboard destination");
      const convert = rows().find(row => row.endpoint === "record.sh");
      check(convert?.argv[0] === "convert-gif", "actual GIF conversion stage runs inert helper");
      if (overlay.recordState !== "")
        return;
      phase = "finish";
    } else if (phase === "finish") {
      current = false;
      check(main.captureAction(selected) === null, "retired overlay origin refuses");
      console.log("CAPTURE_OVERLAY: PASS " + scenario);
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
