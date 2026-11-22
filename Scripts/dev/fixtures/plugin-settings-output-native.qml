import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_OUTPUT_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_OUTPUT_SCOPE")
  readonly property string mode: Quickshell.env("PHA_OUTPUT_MODE")
  readonly property string boundary: Quickshell.env("PHA_OUTPUT_BOUNDARY")
  readonly property string base: Quickshell.env("PHA_OUTPUT_CASE")
  readonly property bool display: plugin === "display-settings"
  readonly property string field: display ? "niriConfigPath" : "gridSize"
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var panel: null
  property var receipt: null
  property bool started: false
  property string phase: "startup"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string diskBoundary: ""
  property string afterDisk: ""
  property string actionBoundary: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expected
    path: root.base + "/expectations.json"
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
    implicitWidth: 1400
    implicitHeight: 900
    Item {
      id: content
      width: 1400
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
      throw new Error("OUTPUT_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
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
    if (object.item) {
      const found = find(object.item, predicate, seen);
      if (found)
        return found;
    }
    for (const list of [object.data, object.children, object.instances]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (const child of list) {
        const found = find(child, predicate, seen);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    const component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    const item = PluginLoader.createObject(plugin, entry, component, content, context, {});
    check(item, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), translations = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, translations, translations, {});
        Service.loadedPlugins = {
          [plugin]: {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                   kind: "bar",
                                                                   list: "global",
                                                                   section: "left",
                                                                   index: index
                                                                 }));
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expected.reload();
    expected.waitForJob();
    const document = JSON.parse(expected.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, document.shared);
    return [shared].concat(document.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    return [api].concat(contexts).every((context, index) => context.pluginSettings[field] === values(name)[index][field]);
  }
  function probe(name, next) {
    diskBoundary = name;
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_OUTPUT_DISK"), base, Quickshell.env("PHA_OUTPUT_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = next;
  }
  function edit() {
    const control = find(popup.settingsPage, item => item.label === api.tr(display ? "settings.niriConfigPath.label" : "settings.gridSize.label") && item.editCommitted !== undefined);
    check(control, "actual field control");
    control.text = display ? base + "/Selected.kdl" : "25";
    control.editCommitted();
    check(popup._pageApi.field(field).value === (display ? base + "/Selected.kdl" : 25), "actual control intent");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field " + key);
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function action(name) {
    actionBoundary = name;
    if (!panel)
      panel = create("panel", target);
    if (display)
      main.refresh(target.settingsContext);
    else
      main.refreshOutputs(target.settingsContext);
    phase = "effect";
  }
  function effect() {
    if ((display ? panel.loading : main.isRefreshing) || Date.now() - since < 300)
      return;
    const selected = values(actionBoundary)[scope === "shared" ? 0 : 1];
    if (display) {
      const path = selected.niriConfigPath;
      const name = path.startsWith("~/") ? "Default" : path.split("/").pop().replace(".kdl", "");
      check(panel.niriOutputs.length === 1 && panel.niriOutputs[0].name === name && find(panel, item => item.text === name), "selected config path reaches actual parsed Panel card");
      console.log("OUTPUT_NATIVE_EFFECT " + JSON.stringify({
                                                             boundary: actionBoundary,
                                                             path: path,
                                                             card: name
                                                           }));
    } else {
      check(main.draftOutputs.length === 1, "actual output result");
      const step = parseInt(selected.gridSize);
      const x = Math.round(61 / step) * step, y = Math.round(74 / step) * step;
      panel.editPosX = "61";
      panel.editPosY = "74";
      panel.applyTypedPosition();
      check(main.draftOutputs[0].x === x && main.draftOutputs[0].y === y && find(panel, item => item.text === x + ", " + y), "selected grid reaches actual shared draft and Panel child Text");
      console.log("OUTPUT_NATIVE_EFFECT " + JSON.stringify({
                                                             boundary: actionBoundary,
                                                             grid: selected.gridSize,
                                                             x: x,
                                                             y: y
                                                           }));
    }
    if (mode === "cold")
      finish();
    else
      probe(actionBoundary, "finish");
  }
  function finish() {
    console.log("OUTPUT_NATIVE: PASS " + plugin + " " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native/output phase");
    if (phase === "runtime" && contexts.every(context => context.settingsReady))
      phase = "initial";
    else if (phase === "initial") {
      const name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "cold")
        action(name);
      else if (mode === "edit")
        probe("initial", "open-discard");
      else
        phase = mode === "follow" ? "change-base" : "open-reset";
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
      edit();
      check(!popup.requestClose(), "dirty Close refused");
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
      probe("edited", "edited-effect");
    else if (phase === "edited-effect")
      action("edited");
    else if (phase === "open-reset")
      open("reset-page");
    else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-effect");
    else if (phase === "reset-effect")
      action("reset");
    else if (phase === "change-base") {
      api.pluginSettings[field] = display ? base + "/Following.kdl" : 37;
      phase = "base-saving";
      api.saveSettings(result => {
        try {
          check(result.status === "saved", "native inheritance publication");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following"))
      probe("following", "following-effect");
    else if (phase === "following-effect")
      action("following");
    else if (phase === "effect")
      effect();
    else if (phase === "finish")
      finish();
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
