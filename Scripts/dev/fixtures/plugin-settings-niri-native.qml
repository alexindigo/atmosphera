import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_NIRI_CASE")
  readonly property string scope: Quickshell.env("PHA_NIRI_SCOPE")
  readonly property string mode: Quickshell.env("PHA_NIRI_MODE")
  readonly property string boundary: Quickshell.env("PHA_NIRI_BOUNDARY")
  readonly property var input: {
    inputFile.waitForJob();
    return JSON.parse(inputFile.text());
  }
  readonly property string plugin: input.plugin
  readonly property string field: input.field
  property var api: null
  property var contexts: []
  readonly property var target: scope === "shared" ? api : contexts[0]
  property var main: null
  property var bar: null
  property var panel: null
  property var receipt: null
  property bool started: false
  property string phase: "begin"
  property double since: Date.now()
  property string next: ""
  property string effectBoundary: ""
  onPhaseChanged: since = Date.now()
  FileView {
    id: inputFile
    path: root.base + "/input.json"
    blockLoading: true
  }
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
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("complete niri native documents");
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
      throw new Error("NIRI_NATIVE_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
      const found = find(object.item, predicate, seen);
      if (found)
        return found;
    }
    for (const list of [object.data, object.children, object.instances]) {
      if (!list || typeof list.length !== "number")
        continue;
      for (let i = 0; i < list.length; i++) {
        const found = find(list[i], predicate, seen);
        if (found)
          return found;
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
    return [api].concat(contexts).every((context, i) => context.pluginSettings[field] === expected[i][field]);
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
        const component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
        check(component.status === Component.Ready, component.errorString());
        main = PluginLoader.createObject(plugin, "main", component, content, api, {});
        check(main, "actual Main");
        api.mainInstance = main;
        contexts = [0, 1, 2].map(i => PluginInstances.apiFor(plugin, {
                                                               kind: "bar",
                                                               list: "global",
                                                               section: "left",
                                                               index: i
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
    disk.command = ["python3", "-B", Quickshell.env("PHA_NIRI_DISK"), base, Quickshell.env("PHA_NIRI_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(after) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, target, "settings"), "actual scoped page");
    phase = after;
  }
  function edit() {
    const control = find(popup.settingsPage, item => plugin === "niri-auto-tile" ? item.objectName === "settings-range-valueMaxVisible" : item.from === 30 && item.to === 7200);
    check(control, "actual configuration control");
    if (plugin === "niri-auto-tile") {
      control.value = input.editValue;
      control.moved();
    } else
      control.submitValue(input.editValue);
    check(popup._pageApi.field(field).value === input.editValue, "actual field intent");
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
  function action(name) {
    effectBoundary = name;
    const component = Qt.createComponent("file://" + api.pluginDir + "/BarWidget.qml");
    check(component.status === Component.Ready, component.errorString());
    bar = PluginLoader.createObject(plugin, "barWidget", component, content, target, {
                                      screen: Quickshell.screens[0]
                                    });
    check(bar, "actual Bar");
    if (plugin === "niri-auto-tile") {
      const panelComponent = Qt.createComponent("file://" + api.pluginDir + "/Panel.qml");
      check(panelComponent.status === Component.Ready, panelComponent.errorString());
      panel = PluginLoader.createObject(plugin, "panel", panelComponent, content, target, {});
      check(panel, "actual Panel");
    }
    phase = "consumer-ready";
  }
  function drive() {
    check(Date.now() - since < 18000, "finite native phase");
    if (phase === "runtime" && contexts.every(context => context.settingsReady) && Date.now() - since > 500)
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
      api.pluginSettings[field] = input.followValue;
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
      probe("following", "following-effect");
    else if (phase === "following-effect")
      action("following");
    else if (phase === "consumer-ready" && Date.now() - since > 300) {
      // Cold readers activate applied policy explicitly, never by rendering.
      // The original control lacks that contract and is observed unchanged.
      if ((mode === "cold" || mode === "follow") && typeof main.applySettings === "function")
        main.applySettings(target.settingsContext);
      phase = "effect";
    } else if (phase === "effect" && Date.now() - since > 1300) {
      const observed = plugin === "niri-auto-tile" ? {
                                                       maxVisible: main.maxVisible,
                                                       running: main.running,
                                                       barMaxVisible: bar.maxVisible,
                                                       panelMaxVisible: panel.globalMaxVisible
                                                     } : {
        idle: JSON.parse(Settings.data.idle.customCommands),
        lock: Settings.data.hooks.screenLock,
        unlock: Settings.data.hooks.screenUnlock
      };
      console.log("NIRI_NATIVE_CONSUMER " + JSON.stringify(observed));
      if (mode === "edit" && Quickshell.env("PHA_NIRI_CONTROL") !== "1") {
        if (plugin === "niri-auto-tile")
          panel.selectColumns(2);
        else
          bar._runQuit();
        phase = "runtime-action";
      } else {
        main.destroy();
        main = null;
        phase = "joined";
      }
    } else if (phase === "runtime-action" && target._pendingSettingsSaves === 0 && Date.now() - since > 500) {
      probe("runtime-action", "runtime-restore");
    } else if (phase === "runtime-restore") {
      if (plugin === "niri-auto-tile")
        panel.selectColumns(input.editValue);
      else {
        const menu = find(bar, item => item.model && item.model.length === 6 && item.model[4].action === "toggle");
        check(menu, "actual Screensaver toggle menu");
        menu.triggered("toggle", null);
      }
      phase = "runtime-restoring";
    } else if (phase === "runtime-restoring" && target._pendingSettingsSaves === 0 && Date.now() - since > 500) {
      probe("runtime-restored", "retire");
    } else if (phase === "retire") {
      main.destroy();
      main = null;
      phase = "joined";
    } else if (phase === "joined" && Date.now() - since > 500) {
      driver.stop();
      console.log("NIRI_NATIVE: PASS " + scope + " " + mode + " " + boundary);
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
