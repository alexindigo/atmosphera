import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Modules.Panels.Plugins

ShellRoot {
  readonly property var modelData: Quickshell.screens[0]
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        id: root
        property bool started: false
        property var api: null
        property var main: null
        property var panel: null
        property var instanceApi: null
        readonly property var slot: slotLoader.item
        property bool ownerAtUnload: false
        property bool receipt: false
        property bool unloaded: false
        property bool completed: false
        property bool held: false
        property bool failedSave: false
        readonly property string mode: Quickshell.env("PLUGIN_UNLOAD_CASE")
        readonly property bool placement: mode === "placement" || mode === "placement-held"
        readonly property bool cold: Quickshell.env("PLUGIN_UNLOAD_COLD") === "1"
        readonly property string name: "notes-scratchpad"
        readonly property string expected: "unsaved scratchpad destruction consumer"
        readonly property var address: ({kind: "bar", list: "global", section: "left", index: 0})
        function check(ok, label) { if (!ok) throw new Error("PLUGIN_UNLOAD_ASSERT: " + label); }
        function fail(error) { console.error(String(error)); Qt.exit(2); }
        function guard(callback) { try { callback(); } catch (error) { fail(error); } }
        function passed() { console.log("PLUGIN_UNLOAD: PASS"); Qt.exit(0); }
        function begin() {
          if (started || !Settings.isLoaded) return;
          started = true;
          Service._openSettingsOwner(name, function (owner) { guard(function () {
            check(owner && owner.status === "Ready", "actual native owner");
            var manifest = JSON.parse(Quickshell.env("PLUGIN_UNLOAD_MANIFEST"));
            api = Service.createPluginAPI(name, manifest, owner, {}, {}, {});
            var registered = Object.assign({}, Service.loadedPlugins);
            registered[name] = {manifest: manifest, api: api}; Service.loadedPlugins = registered;
            if (cold) {
              if (placement) {
                PluginInstances.openRuntime(api, address, function (result) { guard(function () {
                  check(result.status === "opened" && result.editor.values.scratchpadContent === expected, "cold placement consumer");
                  result.editor.detach(); console.log("PLUGIN_UNLOAD: COLD_PASS"); Qt.exit(0);
                }); });
              } else {
                check(api.pluginSettings.scratchpadContent === (mode === "manual-unsaved" ? "original" : expected), "cold shared consumer");
                console.log("PLUGIN_UNLOAD: COLD_PASS"); Qt.exit(0);
              }
              return;
            }
            if (mode === "closed-api") {
              owner.detach();
              api.saveSettings(function (result) { guard(function () {
                check(result.status === "failed", "closed API delivers a failed receipt"); passed();
              }); });
              return;
            }
            Service.pluginContainer = root;
            var installed = Object.assign({}, Registry.installedPlugins); installed[name] = manifest; Registry.installedPlugins = installed;
            var component = Qt.createComponent("file://" + api.pluginDir + "/Main.qml");
            check(component.status === Component.Ready, component.errorString());
            main = PluginLoader.createObject(name, "main", component, root, api, {});
            check(main !== null, "actual notes Main"); api.mainInstance = main;
            var loaded = Object.assign({}, Service.loadedPlugins);
            loaded[name] = {manifest: manifest, api: api, mainInstance: main}; Service.loadedPlugins = loaded;
            if (mode === "manual-unsaved") {
              api.pluginSettings.scratchpadContent = "unrequested manual edit";
              retire(); return;
            }
            if (placement) {
              Settings.data.bar.widgets.left = [{id: "plugin:" + name}];
              Settings.saveResult(function (saved) { guard(function () {
                check(saved.status !== "failed", "placement baseline");
                instanceApi = PluginInstances.apiFor(name, address);
                function ready() {
                  if (!instanceApi.settingsReady) return;
                  instanceApi.settingsReadyChanged.disconnect(ready);
                  Qt.callLater(function () { root.guard(function () { root.createPanel(root.instanceApi); }); });
                }
                instanceApi.settingsReadyChanged.connect(ready); ready();
              }); });
            } else createPanel(api);
          }); });
        }
        function createPanel(selectedApi) {
          if (placement) selectedApi.runtime.completed.connect(function (result) {
            if (["saved", "nothing_to_save"].indexOf(result.status) !== -1) root.receipt = true;
          });
          var component = Qt.createComponent("file://" + api.pluginDir + "/Panel.qml");
          check(component.status === Component.Ready, component.errorString());
          if (mode === "panel-slot") {
            slot.currentPluginId = name; slot.currentPluginApi = api; slot.contentLoader = panelLoader;
            slot.finalizePluginLoad(name, component, api); panel = slot.pluginInstance;
          } else {
            panel = PluginLoader.createObject(name, "panel", component, mode === "destruction" || mode === "reload-held" || mode === "failed-save" ? main : root,
              selectedApi, {screen: Quickshell.screens[0]});
          }
          check(panel !== null, "actual scratchpad Panel");
          Qt.callLater(function () { guard(function () { panel.textContent = expected; retire(); }); });
        }
        function retire() {
          if (mode === "placement-held") { enableFile.setText("1"); enableFile.waitForJob(); }
          if (mode === "reload-held") check(Service.reloadPlugin(name), "reload accepted");
          else Service.unloadPlugin(name, true, function (result) { guard(function () {
            check(ownerAtUnload, "unload observers retain preferences");
            if (mode === "failed-save" && result.status === "failed") {
              failedSave = true;
              check(!api.settingsOwner.closed && Service._settingsOwners[name] === api.settingsOwner, "failed work retained without recreation");
              api.saveSettings(function (saved) { guard(function () {
                check(saved.status !== "failed", "explicit same-owner Retry");
                Service.unloadPlugin(name, true, finish);
              }); });
              return;
            }
            finish(result);
          }); });
          if (placement) lateDestruction.start();
          if (mode === "reload-held") heldCheck.start();
        }
        function finish(result) { guard(function () {
          check(result.status !== "failed", "publication settled before unload completion");
          check(mode !== "failed-save" || failedSave, "actual failed publication preceded explicit Retry");
          check(receipt === (mode !== "manual-unsaved"), "requested publication receipt");
          check(api.settingsOwner === null || api.settingsOwner.closed, "owner retired after last consumer");
          if (placement) check(instanceApi === null, "placement API destroyed last");
          if (mode === "panel-slot") check(slot.currentPluginId === "" && panelLoader.item === null, "independent panel-slot content retired");
          persisted.reload(); persisted.waitForJob();
          check(JSON.parse(persisted.text()).scratchpadContent === (placement || mode === "manual-unsaved" ? "original" : expected), "shared disk publication");
          completed = true; passed();
        }); }
        Connections {
          target: Service
          function onPluginUnloaded(pluginId) {
            if (pluginId !== root.name) return;
            root.ownerAtUnload = root.api.pluginSettings !== null; root.unloaded = true;
          }
          function onPluginSettingsCompleted(pluginId, result) {
            if (pluginId === root.name && ["saved", "nothing_to_save"].indexOf(result.status) !== -1) root.receipt = true;
          }
          function onPluginLoaded(pluginId) { if (pluginId === root.name && root.mode === "reload-held") root.guard(function () {
            root.check(root.held, "no replacement owner before held native publication");
            root.check(Service.getPluginAPI(pluginId).pluginSettings.scratchpadContent === root.expected, "replacement owner reads final destruction save");
            root.completed = true; root.passed();
          }); }
        }
        Timer {
          id: lateDestruction; interval: 150
          onTriggered: root.guard(function () {
            root.check(root.unloaded && !root.completed && root.api.pluginSettings !== null && root.instanceApi.settingsReady, "independent placement lifetime retained");
            root.panel.destroy();
            if (root.mode === "placement-held") heldCheck.start();
          })
        }
        Timer {
          id: heldCheck; interval: 150
          onTriggered: root.guard(function () {
            root.check(root.unloaded && !root.completed && root.api.pluginSettings !== null && !Service.isPluginLoaded(root.name), "pending real publication owns retirement");
            root.held = true; console.log("PLUGIN_UNLOAD: HELD_PASS");
          })
        }
        Loader { id: panelLoader; active: false }
        Loader {
          id: slotLoader
          active: Settings.isLoaded
          sourceComponent: PluginPanelSlot { screen: Quickshell.screens[0]; visible: false }
        }
        FileView { id: persisted; path: Settings.configDir + "settings/plugins/notes-scratchpad.json"; printErrors: false }
        FileView { id: enableFile; path: Quickshell.env("PLUGIN_UNLOAD_ENABLE"); printErrors: false }
        Connections { target: Settings; function onSettingsLoaded() { root.begin(); } }
        Component.onCompleted: Qt.callLater(begin)
        Timer { interval: 25000; running: true; onTriggered: root.fail("unload deadline " + root.mode) }
      }
    }
  }
}
