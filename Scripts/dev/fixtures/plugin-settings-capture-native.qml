// Actual capture pages/native owners and originating actions; helpers are inert.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_CAPTURE_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_CAPTURE_SCOPE")
  readonly property string mode: Quickshell.env("PHA_CAPTURE_MODE")
  readonly property string boundary: Quickshell.env("PHA_CAPTURE_BOUNDARY")
  readonly property string base: Quickshell.env("PHA_CAPTURE_CASE")
  readonly property bool control: Quickshell.env("PHA_CAPTURE_CONTROL") === "1"
  readonly property bool recorder: plugin === "screen-recorder"
  readonly property string field: recorder ? "directory" : "recordingSavePath"
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var views: []
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property string afterAction: ""
  property string actionBoundary: ""
  property int actionIndex: 0
  property int requestCount: 0
  property double actionSince: 0
  property var pendingPanel: null
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requestsFile
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete native documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: content
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("CAPTURE_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
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
      for (var i = 0; i < object.count; ++i) {
        const found = find(object.objectAt(i), predicate);
        if (found)
          return found;
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
  function create(entry, context) {
    const component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    const item = PluginLoader.createObject(plugin, entry, component, content, context, {
                                             screen: Quickshell.screens[0]
                                           });
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    const manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    const registry = {};
    registry[plugin] = manifest;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner !== null, "native plugin owner");
        api = Service.createPluginAPI(plugin, manifest, owner, dictionary, dictionary, {});
        const loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        const contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                         kind: "bar",
                                                                         list: "global",
                                                                         section: "left",
                                                                         index: index
                                                                       }));
        selected = contexts[0];
        sibling = contexts[1];
        inherited = contexts[2];
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expectedFile.reload();
    expectedFile.waitForJob();
    const expected = JSON.parse(expectedFile.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [shared].concat(expected.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    return views.every((view, index) => view.api.pluginSettings[field] === values(name)[index][field]) && (!recorder || main.isAvailable);
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_CAPTURE_DISK"), base, Quickshell.env("PHA_CAPTURE_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    const label = api.tr(recorder ? "settings.general.output-folder" : "settings.recordingSavePath.label");
    const control = find(popup.settingsPage, item => item.label === label && item.inputEditCommitted !== undefined);
    check(control, "actual output folder control");
    control.text = base + "/edited-output";
    control.inputEditCommitted();
    check(popup._pageApi.field(field).value === base + "/edited-output", "actual folder intent");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field: " + key);
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function requests() {
    requestsFile.reload();
    requestsFile.waitForJob();
    return String(requestsFile.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function startActions(name, next) {
    actionBoundary = name;
    afterAction = next;
    actionIndex = scope === "shared" ? 0 : 1;
    phase = "action-start";
  }
  function actions() {
    const view = views[actionIndex], expected = values(actionBoundary)[actionIndex];
    if (phase === "action-start") {
      if (recorder && (main.isPending || main.isRecording) || !recorder && (main.active || main.recordingCheckTarget !== ""))
        return;
      requestCount = requests().length;
      actionSince = Date.now();
      if (recorder)
        view.bar.clicked();
      else {
        pendingPanel = create("panel", view.api);
        const button = find(pendingPanel, item => item.text === api.tr("panel.target.record") && item.clicked !== undefined);
        check(button, "actual originating record button");
        button.clicked();
        pendingPanel.destroy();
        pendingPanel = null;
      }
      phase = recorder ? "action-wait" : "selector";
    } else if (phase === "selector") {
      if (!main.active)
        return;
      const selector = find(main, item => typeof item.finish === "function");
      if (!selector)
        return;
      selector.dragStartX = 1;
      selector.dragStartY = 1;
      selector.draggingX = 21;
      selector.draggingY = 21;
      selector.mouseButton = Qt.LeftButton;
      selector.finish();
      phase = "action-wait";
    } else {
      const rows = requests();
      if (rows.length <= requestCount || Date.now() - actionSince < 220 || recorder && (main.isPending || main.isRecording) || !recorder && main.active && !control)
        return;
      check(rows.length === requestCount + 1, "one physical action owner");
      const row = rows[requestCount], output = row.argv[row.argv.indexOf(recorder ? "-o" : "--dir") + 1];
      const wanted = (expected[field] || base + "/home/Videos").replace(/^~/, base + "/home");
      check(recorder ? output.startsWith(wanted + "/") : output === wanted, "actual inert capture endpoint receives selected output");
      check(recorder ? row.argv[row.argv.indexOf("-f") + 1] === "30" : !row.argv.includes("--notify"), "untouched capture policy preserved");
      console.log("CAPTURE_ACTION " + JSON.stringify({
                                                       boundary: actionBoundary,
                                                       index: actionIndex,
                                                       request: row
                                                     }));
      phase = afterAction;
    }
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native/action phase deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      views = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: recorder ? create("barWidget", context) : null
      }));
      phase = "initial";
    } else if (phase === "initial") {
      const name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      // Each engine observes one admitted operation, not a rapid open/destroy
      // loop of physical selector windows. Complete documents and all four
      // native contexts are still checked independently at every boundary.
      if (mode === "cold")
        startActions(name, "finish");
      else
        phase = mode === "edit" ? "initial-disk" : mode === "follow" ? "change-base" : "open-reset";
    } else if (phase === "initial-disk")
      probe("initial", "open-discard");
    else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited"))
      probe("edited", "edited-actions");
    else if (phase === "edited-actions")
      startActions("edited", "finish");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-final-actions");
    else if (phase === "reset-final-actions")
      startActions("reset", "finish");
    else if (phase === "change-base") {
      api.pluginSettings[field] = base + "/following-output";
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "native inherited publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-actions");
    else if (phase === "following-actions")
      startActions("following", "retire");
    else if (phase === "retire") {
      requestCount = requests().length;
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main.capturePolicy(selected.settingsContext) === null, "retired native capture refuses");
      actionSince = Date.now();
      phase = "retired-check";
    } else if (phase === "retired-check" && Date.now() - actionSince > 220) {
      check(requests().length === requestCount, "retirement has no new effect");
      phase = "finish";
    } else if (["action-start", "action-wait", "selector"].includes(phase))
      actions();
    else if (phase === "finish") {
      console.log("CAPTURE_NATIVE: PASS " + plugin + " " + scope + " " + mode + " " + boundary);
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
        root.fail(error);
      }
    }
  }
  Component.onCompleted: begin()
}
