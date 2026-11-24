// Real native runtime writers; external actions use recorded inert endpoints only.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_ACTION_PLUGIN")
  readonly property bool syncthing: plugin === "syncthing-status"
  property bool started: false
  property var api: null
  property var selected: null
  property var sibling: null
  property var main: null
  property var client: null
  property var capturedContext: null
  property var oldWorker: null
  property var panel: null
  property var receipt: null
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property string afterDisk: ""
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
    id: held
    path: Quickshell.env("PHA_ACTION_CASE") + "/action-held"
    blockLoading: true
  }
  Process {
    id: release
    command: ["touch", Quickshell.env("PHA_ACTION_CASE") + "/release"]
  }
  Process {
    id: disk
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (code) {
      if (code !== 0)
        root.fail("independent native action document differs: " + disk.stdout.text + disk.stderr.text);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 700
    implicitHeight: 900
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("QUERY_ACTION_ASSERT: " + plugin + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var result = find(child, predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject(plugin, entry, component, content, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(item !== null, "actual " + entry + " constructs");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifest.waitForJob();
    dictionary.waitForJob();
    var value = JSON.parse(manifest.text()), words = JSON.parse(dictionary.text());
    var registry = {};
    registry[plugin] = value;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner !== null, "native shared owner");
        api = Service.createPluginAPI(plugin, value, owner, words, words, {});
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor(plugin, {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor(plugin, {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function probe(name, next) {
    afterDisk = next;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_ACTION_DISK"), Quickshell.env("PHA_ACTION_CASE"), Quickshell.env("PHA_ACTION_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite operation deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady) {
      capturedContext = selected.settingsContext;
      client = main.settingsConsumerFor(capturedContext);
      panel = create("panel", selected);
      phase = "initial";
    } else if (phase === "initial") {
      if (syncthing ? client.busy || client.state !== "idle" : client.pods.length !== 1)
        return;
      check((syncthing ? panel.mainInst : panel.main) === client, "actual Panel uses originating selected client");
      probe("initial", "refuse");
    } else if (phase === "refuse") {
      if (syncthing)
        check(!client.toggleFolder("foreign", api) && !client.setFolderSelection(["foreign"], sibling), "foreign runtime writer refused");
      probe("refused", "act");
    } else if (phase === "act") {
      if (syncthing) {
        receipt = null;
        check(client.toggleFolder("extra", selected), "originating native folder writer admitted");
        phase = "changed";
      } else {
        oldWorker = client._worker;
        client.openTerminal(["get", "pods"]);
        client.deleteResource("pods", "captured-pod");
        phase = "held";
      }
    } else if (phase === "held") {
      held.reload();
      held.waitForJob();
      if (held.text() !== "held")
        return;
      selected.pluginSettings.kubeconfigPath = "replacement";
      selected.saveSettings(function (result) {
        receipt = result;
      });
      check(client.kubeconfigPath === "replacement" && !oldWorker.active, "native source handoff fences held action worker");
      release.running = true;
      phase = "changed";
    } else if (phase === "changed") {
      if (syncthing) {
        if (!receipt || (receipt.status !== "saved" && receipt.status !== "nothing_to_save"))
          return;
        check(client.folderIds.length === 2, "originating native folder writer updates selected leaf");
        if (client.busy || client.folderIds.length !== 2 || client.folders.length !== 2)
          return;
        check(client.resolvedUrl === "http://selected.invalid" && client.folders[1].id === "extra", "native folder write reaches selected helper generation");
        check(find(panel, item => item.text === "extra"), "actual Panel folder Text consumes native writer result");
      } else {
        if (!receipt || receipt.status !== "saved" || client.pods[0]?.name !== "replacement-pod")
          return;
        check(client.activeContext === "replacement" && client.activeNamespace === "replacement-ns", "replacement query consumer has captured source targets");
        client.restartResource("deployments", "replacement-deploy");
      }
      probe("changed", "retire");
    } else if (phase === "retire") {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !capturedContext.current() && Date.now() - phaseStarted > 500) {
      check(main._settingsConsumers.size === 0 && main.settingsConsumerFor(capturedContext) === null, "retired native context cannot reacquire action client");
      probe("retired", "finish");
    } else if (phase === "finish") {
      console.log("QUERY_ACTIONS: PASS " + plugin);
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
    function onPluginSettingsCompleted(pluginId, result) {
      if (pluginId === root.plugin) {
        root.receipt = result;
        console.log("QUERY_ACTION_RECEIPT " + JSON.stringify(result));
      }
    }
  }
  Timer {
    interval: 80
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
