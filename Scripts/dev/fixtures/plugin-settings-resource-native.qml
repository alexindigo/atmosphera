import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_RESOURCE_CASE")
  readonly property string scope: Quickshell.env("PHA_RESOURCE_SCOPE")
  readonly property string mode: Quickshell.env("PHA_RESOURCE_MODE")
  readonly property string boundary: Quickshell.env("PHA_RESOURCE_BOUNDARY")
  readonly property string plugin: {
    input.waitForJob();
    return JSON.parse(input.text()).plugin;
  }
  readonly property string field: {
    input.waitForJob();
    return JSON.parse(input.text()).field;
  }
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var bar: null
  property var panel: null
  property var receipt: null
  property var runtimeReceipt: null
  property bool started: false
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property string next: ""
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
    id: expectations
    path: root.base + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: input
    path: root.base + "/input.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete resource native documents");
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
      throw new Error("RESOURCE_NATIVE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    expectations.reload();
    expectations.waitForJob();
    const document = JSON.parse(expectations.text())[name];
    const shared = Object.assign({}, api.manifest.metadata.defaultSettings, document.shared);
    return [shared].concat(document.bar.widgets.left.map(row => Object.assign({}, shared, row.instanceSettings || {})));
  }
  function ready(name) {
    const expected = values(name);
    return [api].concat(contexts).every((context, index) => context.pluginSettings[field] === expected[index][field]);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    input.waitForJob();
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
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
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
    disk.command = ["python3", "-B", Quickshell.env("PHA_RESOURCE_DISK"), base, Quickshell.env("PHA_RESOURCE_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = after;
  }
  function edit() {
    const control = find(popup.settingsPage, item => field === "port" ? item.from === 1 && item.to === 65535 : item.placeholderText === "noctalia-clamshell");
    check(control, "actual configuration control");
    const value = JSON.parse(input.text()).editValue;
    if (field === "port")
      control.submitValue(value);
    else {
      control.text = value;
      control.editCommitted();
    }
    check(popup._pageApi.field(field).value === value, "actual field intent");
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
  function action(name) {
    actionBoundary = name;
    const component = Qt.createComponent("file://" + api.pluginDir + "/BarWidget.qml");
    check(component.status === Component.Ready, component.errorString());
    bar = PluginLoader.createObject(plugin, "barWidget", component, content, target, {
                                      screen: Quickshell.screens[0]
                                    });
    check(bar, "actual originating Bar");
    if (field === "port") {
      const panelComponent = Qt.createComponent("file://" + api.pluginDir + "/Panel.qml");
      check(panelComponent.status === Component.Ready, panelComponent.errorString());
      panel = PluginLoader.createObject(plugin, "panel", panelComponent, content, target, {});
      check(panel, "actual Panel");
    }
    phase = "consumer-ready";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite resource native phase");
    if (phase === "runtime" && contexts.every(context => context.settingsReady) && (field === "port" ? main.serviceRunning : main.inhibitorActive))
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
      api.pluginSettings[field] = JSON.parse(input.text()).followValue;
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
    else if (phase === "consumer-ready" && Date.now() - since > 300) {
      if (field === "port") {
        const menu = find(bar, item => item.model && item.model.length === 3 && item.model[1].action === "restart");
        check(menu, "actual Bar restart menu");
        menu.triggered("restart", null);
      } else if (mode === "cold" || mode === "follow")
        main.applySettings(target.settingsContext);
      phase = "effect";
    } else if (phase === "effect" && (field === "port" ? main.serviceRunning : main.inhibitorActive) && Date.now() - since > 1800) {
      if (field === "port") {
        const label = find(panel, item => typeof item.text === "string" && item.text.indexOf(main.serverUrl) !== -1);
        check(label, "actual Panel URL child");
        console.log("RESOURCE_NATIVE_CONSUMER " + JSON.stringify({
                                                                   url: main.serverUrl,
                                                                   count: main.runningCount,
                                                                   rendered: label.text.indexOf(String(main.runningCount)) !== -1
                                                                 }));
      } else
        console.log("RESOURCE_NATIVE_CONSUMER " + JSON.stringify({
                                                                   who: main.inhibitorWho,
                                                                   active: main.inhibitorActive,
                                                                   barVisible: bar.visible
                                                                 }));
      if (field !== "port" && mode === "edit" && Quickshell.env("PHA_RESOURCE_CONTROL") !== "1") {
        runtimeReceipt = null;
        bar.clicked();
        phase = "runtime-disabled";
      } else {
        main.destroy();
        main = null;
        phase = "joined";
      }
    } else if (phase === "runtime-disabled" && runtimeReceipt && target._pendingSettingsSaves === 0 && !main.inhibitorActive && !main.enabled) {
      check(runtimeReceipt.status === "saved", "originating disable acknowledged");
      probe("runtime-disabled", "runtime-enable");
    } else if (phase === "runtime-enable") {
      const component = Qt.createComponent("file://" + api.pluginDir + "/ControlCenterWidget.qml");
      check(component.status === Component.Ready, component.errorString());
      const shortcut = PluginLoader.createObject(plugin, "controlCenterWidget", component, content, target, {
                                                   screen: Quickshell.screens[0]
                                                 });
      check(shortcut, "actual originating CC");
      runtimeReceipt = null;
      shortcut.clicked();
      phase = "runtime-enabled";
    } else if (phase === "runtime-enabled" && runtimeReceipt && target._pendingSettingsSaves === 0 && main.inhibitorActive && main.enabled) {
      check(runtimeReceipt.status === "saved", "originating enable acknowledged");
      probe("runtime-enabled", "runtime-finish");
    } else if (phase === "runtime-finish") {
      main.destroy();
      main = null;
      phase = "joined";
    } else if (phase === "joined" && Date.now() - since > 400) {
      driver.stop();
      console.log("RESOURCE_NATIVE: PASS " + scope + " " + mode + " " + boundary);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Connections {
    target: Service
    function onPluginSettingsCompleted(id, result) {
      if (id === root.plugin)
        root.runtimeReceipt = result;
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
