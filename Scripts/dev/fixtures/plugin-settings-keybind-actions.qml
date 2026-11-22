import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string casePath: Quickshell.env("KBD_ACTION_CASE")
  readonly property string scope: Quickshell.env("KBD_ACTION_SCOPE")
  readonly property string mode: Quickshell.env("KBD_ACTION_MODE")
  property var api: null
  property var selected: null
  property var sibling: null
  property var target: null
  property var main: null
  property var panel: null
  property var otherPanel: null
  property var client: null
  property var origin: null
  property var retiredClient: null
  property string bindId: "|32|b|000|exec:fixture"
  property string phase: "startup"
  property string next: ""
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property bool started: false
  FileView {
    id: manifest
    path: Settings.configDir + "plugins/keybind-cheatsheet/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionary
    path: Settings.configDir + "plugins/keybind-cheatsheet/i18n/en.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent document/permission boundary");
      else
        root.phase = root.next;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1400
    implicitHeight: 950
    Item {
      id: scene
      width: 1400
      height: 950
    }
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("KEYBIND_ACTION_ASSERT: " + phase + ": " + label);
    console.log("KEYBIND_ACTION_CHECK: " + label);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function create(entry, runtime) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("keybind-cheatsheet", entry, component, scene, runtime, {});
    check(item, "actual " + entry);
    return item;
  }
  function find(item, predicate, seen) {
    seen = seen || new Set();
    if (!item || seen.has(item))
      return null;
    seen.add(item);
    if (predicate(item))
      return item;
    for (var list of [item.data, item.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child, predicate, seen);
        if (found)
          return found;
      }
    }
    return null;
  }
  function bind(view) {
    for (var category of view.rawCategories)
      for (var row of category.binds)
        if (row.bindId === bindId)
          return row;
    return null;
  }
  function probe(boundary, after) {
    next = after;
    phase = "disk";
    disk.command = ["/usr/bin/python3", "-B", Quickshell.env("KBD_ACTION_DISK"), casePath, Quickshell.env("KBD_ACTION_OUTPUT"), boundary];
    disk.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    var descriptor = JSON.parse(manifest.text()), dict = JSON.parse(dictionary.text());
    Registry.installedPlugins = {
      "keybind-cheatsheet": descriptor
    };
    Service._openSettingsOwner("keybind-cheatsheet", function (owner) {
      try {
        check(owner, "actual native shared owner");
        api = Service.createPluginAPI("keybind-cheatsheet", descriptor, owner, dict, dict, {});
        Service.loadedPlugins = {
          "keybind-cheatsheet": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("keybind-cheatsheet", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("keybind-cheatsheet", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        phase = "ready";
      } catch (error) {
        fail(error);
      }
    });
  }
  function act(description, hidden) {
    target._lastSettingsSave = null;
    check(hidden ? panel.hideBind(bindId) : panel.saveBindDescription(bindId, description), "actual originating Panel writer admitted");
  }
  function saved() {
    return target._lastSettingsSave && target._pendingSettingsSaves === 0;
  }
  function accepted() {
    return saved() && ["saved", "nothing_to_save"].includes(target._lastSettingsSave.status);
  }
  function drive() {
    if (Date.now() - since >= 18000)
      throw new Error("KEYBIND_ACTION_ASSERT: " + phase + ": finite native action phase");
    if (phase === "described" && scope === "instance" && !target._lastSettingsSave && api._lastSettingsSave)
      check(false, "runtime writer publishes through originating native API");
    if (phase === "ready" && selected.settingsReady && sibling.settingsReady) {
      target = scope === "instance" ? selected : api;
      panel = create("panel", target);
      otherPanel = create("panel", sibling);
      client = main.clientFor(target);
      phase = "parsed";
    } else if (phase === "parsed" && client.worker && !client.worker.isCurrentlyParsing && otherPanel.rawCategories.length) {
      check(panel.settingsConsumer === client && otherPanel.settingsConsumer !== client, "native context clients remain distinct");
      if (mode !== "warm") {
        check(!bind(panel) && bind(otherPanel)?.undescribed, "cold hidden choice only affects originating consumer");
        probe("hidden", mode === "retire" ? "retire" : "finish");
      } else {
        check(bind(panel)?.undescribed, "actual hyprctl undescribed bind");
        probe("initial", "describe");
      }
    } else if (phase === "describe") {
      act("Selected description", false);
      phase = "described";
    } else if (phase === "described" && accepted() && bind(panel)?.desc === "Selected description" && find(panel, item => item.text === "Selected description")) {
      check(find(panel, item => item.text === "Selected description"), "actual runtime description Text");
      check(bind(otherPanel)?.undescribed, "overridden sibling keeps original result");
      probe("described", "block");
    } else if (phase === "block")
      probe("block", "failed-write");
    else if (phase === "failed-write") {
      act("Retry description", false);
      phase = "failed";
    } else if (phase === "failed" && saved()) {
      check(target._lastSettingsSave.status === "failed", "actual native permission failure is not acknowledged");
      check(target.pluginSettings.bindOverrides[bindId].desc === "Retry description", "failed desired input retained");
      probe("failed", "unblock");
    } else if (phase === "unblock")
      probe("unblock", "retry");
    else if (phase === "retry") {
      act("Retry description", false);
      phase = "retried";
    } else if (phase === "retried" && accepted() && bind(panel)?.desc === "Retry description" && find(panel, item => item.text === "Retry description")) {
      check(find(panel, item => item.text === "Retry description"), "retry reaches actual description Text");
      probe("retried", "clear");
    } else if (phase === "clear") {
      act("", false);
      phase = "cleared";
    } else if (phase === "cleared" && accepted() && bind(panel)?.undescribed)
      probe("cleared", "hide");
    else if (phase === "hide") {
      act("", true);
      phase = "hidden";
    } else if (phase === "hidden" && accepted() && !bind(panel)) {
      check(bind(otherPanel)?.undescribed, "hide preserves overridden sibling");
      probe("hidden", "finish");
    } else if (phase === "retire") {
      // Real owning-list replacement, not a plain-JS test-context flag.
      origin = selected.settingsContext;
      retiredClient = main.clientFor(selected);
      Settings.data.bar.widgets.left = Settings.data.bar.widgets.left.slice(1);
      phase = "retired";
    } else if (phase === "retired" && !origin.current()) {
      check(!main.updateBind(selected, bindId, "must not publish", false), "retired native writer refuses shifted sibling");
      phase = "quiescent";
    } else if (phase === "quiescent" && Date.now() - since > 250) {
      check(retiredClient === null && !main._settingsConsumers.has(origin), "actual native retirement destroys selected parser client");
      phase = "retirement-save";
      Settings.store.saveSelected([["bar", "widgets", "left"]], result => {
        try {
          check(["saved", "nothing_to_save"].includes(result.status), "test owning-list removal publication");
          phase = "retirement-saved";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "retirement-saved") {
      probe("retired", "finish");
    } else if (phase === "finish") {
      console.log("KEYBIND_ACTIONS: PASS " + scope + " " + mode);
      Qt.exit(0);
    }
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
}
