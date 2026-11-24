import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_OBS_CASE")
  readonly property string plugin: "obs-control"
  readonly property string scope: Quickshell.env("PHA_OBS_SCOPE")
  readonly property string mode: Quickshell.env("PHA_OBS_MODE")
  readonly property string boundary: Quickshell.env("PHA_OBS_BOUNDARY")
  readonly property string field: "barLabelMode"
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var bars: []
  property var centers: []
  property var panels: []
  property var receipt: null
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  property string next: ""
  property string effect: ""
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/obs-control/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/obs-control/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectations
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete OBS native documents");
      else
        root.phase = root.next;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1400
    implicitHeight: 1000
    Item {
      id: content
      width: 1400
      height: 1000
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OBS_NATIVE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
  function values(name) {
    expectations.waitForJob();
    const doc = JSON.parse(expectations.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, doc.shared);
    return [shared].concat(doc.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    const expected = values(name);
    return [api].concat(contexts).every((context, index) => context.pluginSettings[field] === expected[index][field]);
  }
  function create(entry, context) {
    const component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    const item = PluginLoader.createObject(plugin, entry, component, content, context, entry === "barWidget" || entry === "controlCenterWidget" ? {
                                                                                                                                                    screen: Quickshell.screens[0]
                                                                                                                                                  } : {});
    check(item, "actual " + entry);
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    const descriptor = JSON.parse(manifest.text()), words = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      [plugin]: descriptor
    };
    Service._openSettingsOwner(plugin, owner => {
      try {
        check(owner, "native owner");
        api = Service.createPluginAPI(plugin, descriptor, owner, words, words, {});
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
        phase = "initial";
      } catch (error) {
        fail(error);
      }
    });
  }
  function probe(name, after) {
    next = after;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_OBS_DISK"), base, Quickshell.env("PHA_OBS_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = after;
  }
  function edit() {
    const control = find(popup.settingsPage, item => item.currentKey === popup._pageApi.field(field).value && item.model && item.model.length === 3 && item.model[0].key === "icon-only");
    check(control, "actual label combo");
    control.selected("duration");
    check(popup._pageApi.field(field).value === "duration", "actual combo intent");
    for (const key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched " + key);
  }
  function apply(after) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = after;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function observe(name) {
    effect = name;
    const all = [api].concat(contexts);
    bars = all.map(context => create("barWidget", context));
    centers = all.map(context => create("controlCenterWidget", context));
    panels = all.map(context => create("panel", context));
    phase = "consumer";
  }
  function drive() {
    check(Date.now() - since < 15000, "finite native phase");
    if (phase === "initial" && contexts.every(context => context.settingsReady) && main.recording && main.websocket) {
      const name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      if (mode === "cold")
        observe(name);
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
      observe("edited");
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
      observe("reset");
    else if (phase === "change-base") {
      api.pluginSettings[field] = "short-label";
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
      observe("following");
    else if (phase === "consumer" && Date.now() - since > 300) {
      const all = [api].concat(contexts);
      const observations = bars.map((bar, index) => ({
        mode: bar.barLabelMode,
        text: bar.displayText,
        rendered: !!find(bar, item => item.text === bar.displayText && item.visible),
        bar: bar.showInBar,
        cc: centers[index].showShortcut,
        client: typeof main.settingsConsumerFor === "function" && bar.service === main.settingsConsumerFor(all[index].settingsContext) && centers[index].service === bar.service && panels[index].service === bar.service && !!find(centers[index], item => item !== centers[index] && item.service === bar.service)
      }));
      console.log("OBS_NATIVE_CONSUMER " + JSON.stringify(observations));
      bars.concat(centers, panels).forEach(item => item.destroy());
      main.destroy();
      main = null;
      phase = "joined";
    } else if (phase === "joined" && Date.now() - since > 300) {
      driver.stop();
      console.log("OBS_NATIVE: PASS " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
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
