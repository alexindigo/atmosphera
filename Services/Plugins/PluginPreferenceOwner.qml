import QtQuick
import Quickshell
import ConfigQml 1.0
import "../../Helpers/OwnedProcess.js" as OwnedProcess

// Dynamic schema construction is separate from preference ownership. Only
// authored descriptors/defaults reach the compiler; ConfigStore owns all user
// reads, fallback, admission, projection, watching and publication.
QtObject {
  id: root
  required property string pluginId
  required property string pluginDirectory
  required property string userFile
  required property string configFile
  required property string cacheDirectory
  required property string evidenceDirectory
  property var store: null
  property var settingsScope: null
  property var configScope: null
  property var _component: null
  property string status: "Loading"
  property string error: ""
  property bool closed: false
  signal settled
  signal completed(var result)

  function fail(code) {
    if (closed || status !== "Loading") return;
    error = code;
    status = "Error";
    settled();
  }
  function load() {
    OwnedProcess.run(root, ["python3", "-B", Quickshell.shellDir + "/Scripts/python/src/settings/plugin-schema.py",
      "--manifest", pluginDirectory + "/manifest.json", "--overlays", Quickshell.shellDir + "/Configs/plugin-settings-overlays.json",
      "--runtime-store", cacheDirectory, "--plugin-directory", pluginDirectory,
      "--user-file", userFile, "--config-file", configFile, "--evidence-directory", evidenceDirectory], null, function (result) {
      if (root.closed) return;
      var file;
      try { file = JSON.parse(result.stdout).file; } catch (error) {}
      if (!result.success || typeof file !== "string" || !file.startsWith(root.cacheDirectory + "/")) {
        root.fail("plugin-schema"); return;
      }
      var component = Qt.createComponent("file://" + file, Component.Asynchronous);
      root._component = component;
      function construct() {
        if (root.closed) return;
        if (component.status === Component.Error) { root.fail("plugin-schema-component"); return; }
        if (component.status !== Component.Ready || root.store) return;
        root.store = component.createObject(root);
        if (!root.store) { root.fail("plugin-store-construction"); return; }
        function ready() {
          if (root.closed || root.status !== "Loading") return;
          if (root.store.status === ConfigStore.Error) { root.fail("plugin-store"); return; }
          if (!root.store.ready) return;
          root.settingsScope = root.store.scope(["settings"]);
          root.configScope = root.store.scope(["config"], false);
          root.status = "Ready";
          root.settled();
        }
        root.store.statusChanged.connect(ready);
        root.store.completed.connect(function (receipt) { root.completed(receipt); });
        ready();
      }
      component.statusChanged.connect(construct);
      construct();
    });
  }
  function snapshotConfig(callback) {
    if (closed || status !== "Ready") return false;
    // An explicit API read, not a persistence baseline or raw-layer mirror.
    // Enumerate the declared leaves, never QObject machinery or user-file keys.
    var output = Object.create(null);
    for (var path of store.configPaths) {
      var value = configScope.values;
      for (var segment of path) value = value[segment];
      if (value === undefined) continue;
      var parent = output;
      for (var i = 0; i < path.length - 1; ++i) {
        if (!Object.prototype.hasOwnProperty.call(parent, path[i])) parent[path[i]] = Object.create(null);
        parent = parent[path[i]];
      }
      parent[path[path.length - 1]] = store.copyValue(value);
    }
    Qt.callLater(function () { if (!root.closed && typeof callback === "function") callback(output); });
    return true;
  }
  function detach() {
    closed = true;
    if (settingsScope) settingsScope.detach();
    if (configScope) configScope.detach();
    // autoSave=false: deleting a manual owner does not publish unrequested
    // edits. Already requested saves survive through the native shutdown owner.
    if (store) store.destroy();
    settingsScope = null;
    configScope = null;
    store = null;
    status = "Closed";
    settled();
  }
  Component.onCompleted: Qt.callLater(load)
}
