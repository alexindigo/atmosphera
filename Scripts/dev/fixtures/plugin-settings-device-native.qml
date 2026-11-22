import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_DEVICE_CASE")
  readonly property string scope: Quickshell.env("PHA_DEVICE_SCOPE")
  readonly property string plugin: Quickshell.env("PHA_DEVICE_PLUGIN")
  readonly property string mode: Quickshell.env("PHA_DEVICE_MODE")
  readonly property string boundary: Quickshell.env("PHA_DEVICE_BOUNDARY")
  readonly property bool gpu: plugin === "noctalia-supergfxctl"
  readonly property string field: gpu ? "supergfxctl" : "fileBrowser"
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var panel: null
  property var bar: null
  property var receipt: null
  property bool started: false
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string next: ""
  property string actionBoundary: ""
  property int before: 0
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
    id: expectations
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete device native documents");
      else
        root.phase = root.next;
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
      throw new Error("DEVICE_NATIVE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
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
      const child = find(object.item, predicate, seen);
      if (child)
        return child;
    }
    for (const list of [object.data, object.children, object.instances]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (let index = 0; index < list.length; index++) {
        const child = find(list[index], predicate, seen);
        if (child)
          return child;
      }
    }
    return null;
  }
  function normalized(value) {
    if (!value || typeof value !== "object")
      return value;
    if (Array.isArray(value))
      return value.map(normalized);
    const result = {};
    for (const key of Object.keys(value).sort())
      result[key] = normalized(value[key]);
    return result;
  }
  function same(a, b) {
    return JSON.stringify(normalized(a)) === JSON.stringify(normalized(b));
  }
  function values(name) {
    expectations.reload();
    expectations.waitForJob();
    const document = JSON.parse(expectations.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, document.shared);
    return [shared].concat(document.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    const expected = values(name);
    return [api].concat(contexts).every((context, index) => same(context.pluginSettings[field], expected[index][field]));
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
        const component = Qt.createComponent("file://" + api.pluginDir + "/" + descriptor.entryPoints.main);
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject(plugin, "main", component, content, api, {});
        check(main, "actual Main");
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
  function probe(name, after) {
    next = after;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_DEVICE_DISK"), base, Quickshell.env("PHA_DEVICE_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = after;
  }
  function edit() {
    const control = find(popup.settingsPage, item => item.label === api.tr(gpu ? "settings.supergfxctl.patchPending.label" : "settings.file-browser") && (gpu ? item.toggled !== undefined : item.selected !== undefined));
    check(control, "actual device control");
    if (gpu)
      control.toggled(false);
    else
      control.selected("dolphin");
    check(gpu ? popup._pageApi.field(field).value.patchPending === false : popup._pageApi.field(field).value === "dolphin", "actual field intent");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field " + key);
  }
  function apply(after) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = after;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function create(entry) {
    const component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    const item = PluginLoader.createObject(plugin, entry, component, content, target, entry === "barWidget" ? {
                                                                                                                screen: Quickshell.screens[0]
                                                                                                              } : {});
    check(item, "actual " + entry);
    return item;
  }
  function action(name) {
    actionBoundary = name;
    before = rows().length;
    panel = create("panel");
    if (gpu)
      bar = create("barWidget");
    phase = "consumer-ready";
  }
  function effect() {
    if (Date.now() - since < 700 || (gpu ? main.busy : main.loading))
      return;
    const selected = values(actionBoundary)[scope === "shared" ? 0 : 1][field];
    if (gpu) {
      const pending = selected.patchPending ?? true;
      const pill = find(bar, item => item.tooltipText !== undefined && item.forceClose !== undefined);
      check(pill, "actual GPU Bar child");
      check(main.pendingAction === (pending ? 0 : 4) && String(pill.tooltipText).includes("|") === pending, "selected pending policy reaches actual GPU consumer");
    } else {
      const terminal = ["yazi", "ranger", "lf", "nnn"].includes(selected);
      const actions = rows().slice(before);
      check(actions.some(row => row.endpoint === (terminal ? "kitty" : selected) && same(row.argv, terminal ? ["-e", selected, base + "/mounted"] : [base + "/mounted"])), "selected browser reaches actual Panel action endpoint");
    }
    console.log("DEVICE_NATIVE_EFFECT " + JSON.stringify({
                                                           boundary: actionBoundary,
                                                           value: selected
                                                         }));
    if (mode === "cold")
      finish();
    else
      probe(actionBoundary, "finish");
  }
  function finish() {
    driver.stop();
    console.log("DEVICE_NATIVE: PASS " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native device phase");
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
      check(popup._pageApi.field(field).reset(), "staged Reset");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset"))
      probe("reset", "reset-effect");
    else if (phase === "reset-effect")
      action("reset");
    else if (phase === "change-base") {
      api.pluginSettings[field] = gpu ? {
                                          patchPending: false,
                                          polling: false,
                                          pollingInterval: 3000
                                        } : "thunar";
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
    else if (phase === "consumer-ready" && Date.now() - since > 500 && (gpu ? !main.busy : main.devices.length === 1)) {
      const control = find(panel, item => gpu ? item.icon === "refresh" && item.clicked !== undefined : item.text === api.tr("device.action-open") && item.clicked !== undefined);
      check(control, "actual originating Panel action");
      control.clicked();
      phase = "effect";
    } else if (phase === "effect")
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
  Component.onCompleted: begin()
}
