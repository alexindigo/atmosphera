pragma Singleton
import QtQuick
import Quickshell
import ConfigQml 1.0
import "../../Helpers/SettingsListCommands.js" as Lists
import qs.Commons
import qs.Services.Plugins

// Placement addressing and handle lifetime only. Native overlays own live
// values, sparse differences, row mapping, revisions and persistence.
Singleton {
  id: root
  property var _cache: Object.create(null)
  // Presentation invalidation only; never a capture/conflict generation.
  property int revision: 0
  Component { id: apiFactory; PluginInstanceApi {} }
  Component { id: editorFactory; PluginPreferenceEditor {} }
  Connections {
    target: Service
    function onPluginLoaded(pluginId) { root._dropPlugin(pluginId); }
    function onPluginUnloaded(pluginId) { root._dropPlugin(pluginId); }
  }
  Connections {
    target: Settings
    function onEffectiveSettingsChanged(section) {
      if (["bar", "controlCenter", "desktopWidgets"].indexOf(section) !== -1) root.revision++;
    }
  }
  function barList(screenName) {
    return !screenName || Settings.getBarWidgetsForScreen(screenName) === Settings.data.bar.widgets ? "global" : screenName;
  }
  function apiFor(pluginKey, placement) {
    void root.revision;
    var base = Service.getPluginAPI(pluginKey);
    if (!base || !placement) return null;
    var key = JSON.stringify([pluginKey, placement]);
    var cached = _cache[key];
    if (cached && cached.base === base && !cached.api.settingsError) return cached.api;
    if (cached) cached.api.destroy();
    var api = apiFactory.createObject(root, {base: base, placement: Lists.copy(placement)});
    _cache[key] = {base: base, api: api};
    return api;
  }
  function _dropPlugin(pluginKey) {
    for (var key of Object.keys(_cache)) {
      if (_cache[key].base.pluginId === pluginKey) {
        _cache[key].api.destroy();
        delete _cache[key];
      }
    }
    revision++;
  }
  function address(placement) {
    if (!placement || !Number.isSafeInteger(placement.index) || placement.index < 0) return null;
    var result;
    if (placement.kind === "bar" && placement.list === "global" && ["left", "center", "right"].indexOf(placement.section) !== -1)
      return {path: ["bar", "widgets", placement.section], entry: [{index: placement.index}]};
    if (placement.kind === "controlCenter" && ["left", "right"].indexOf(placement.section) !== -1)
      return {path: ["controlCenter", "shortcuts", placement.section], entry: [{index: placement.index}]};
    var monitors;
    var name;
    if (placement.kind === "bar" && ["left", "center", "right"].indexOf(placement.section) !== -1) {
      monitors = Settings.data.bar.screenOverrides;
      name = placement.list;
      result = {path: ["bar", "screenOverrides"], entry: []};
    } else if (placement.kind === "desktop") {
      monitors = Settings.data.desktopWidgets.monitorWidgets;
      name = placement.screenName;
      result = {path: ["desktopWidgets", "monitorWidgets"], entry: []};
    } else return null;
    for (var i = 0; i < monitors.length; ++i) {
      if (monitors[i].name !== name) continue;
      result.entry = [{index: i}, {key: "widgets"}];
      if (placement.kind === "bar") result.entry.push({key: placement.section});
      result.entry.push({index: placement.index});
      return result;
    }
    return null;
  }
  function entryFor(placement) {
    var selected = address(placement);
    if (!selected) return null;
    var value = Settings.data;
    for (var segment of selected.path) value = value[segment];
    for (var selector of selected.entry) {
      if (value === null || value === undefined) return null;
      value = Object.prototype.hasOwnProperty.call(selector, "index") ? value[selector.index] : value[selector.key];
    }
    return value || null;
  }
  function _open(base, placement, mode, callback, previewBase) {
    var active = true;
    var submitted = false;
    var scope = previewBase || (base ? base.settingsHandle : null);
    var main = Settings.store;
    function disconnect() {
      main.completed.disconnect(attempt);
      main.statusChanged.disconnect(attempt);
      Service.pluginLoaded.disconnect(attempt);
      Service.pluginUnloaded.disconnect(attempt);
      if (scope) {
        scope.completed.disconnect(attempt);
        scope.statusChanged.disconnect(attempt);
      }
    }
    function attempt() {
      if (!active || submitted) return;
      if (!scope || Service.getPluginAPI(base.pluginId) !== base || !base.settingsOwner || base.settingsOwner.closed) {
        active = false; disconnect(); callback({status: "failed", error: {code: "overlay-owner"}}); return;
      }
      if (main.status === ConfigStore.Error || main.status === ConfigStore.Closed || main.status === ConfigStore.Closing ||
          scope.status === ConfigStore.Error || scope.status === ConfigStore.Closed || scope.status === ConfigStore.Closing) {
        active = false; disconnect(); callback({status: "failed", error: {code: "overlay-owner"}}); return;
      }
      if (!main.ready) return;
      var selected = address(placement);
      if (!selected) {
        active = false; disconnect(); callback({status: "failed", error: {code: "overlay-identity"}}); return;
      }
      if (!Lists.settled(main.info(selected.path)) || !base.settingsOwner.store.settingsKeys.every(function (key) { return Lists.settled(scope.info([key])); })) return;
      submitted = true;
      disconnect();
      main.openOverlay({mode: mode, base: scope, ownerPath: selected.path,
        ownerGeneration: main.info(selected.path).publicationGeneration,
        entryPath: selected.entry, identityPath: [{key: "id"}], identityValue: "plugin:" + base.pluginId,
        overrideKey: "instanceSettings", mergePolicy: "recursive_objects_replace_lists", differencePolicy: "top_level_omit_equal"}, function (result) {
          if (!active) { if (result.editor) result.editor.detach(); return; }
          active = false;
          callback(result);
        });
    }
    main.completed.connect(attempt);
    main.statusChanged.connect(attempt);
    Service.pluginLoaded.connect(attempt);
    Service.pluginUnloaded.connect(attempt);
    if (scope) {
      scope.completed.connect(attempt);
      scope.statusChanged.connect(attempt);
    }
    Qt.callLater(attempt);
    return function () { if (active) { active = false; if (!submitted) disconnect(); } };
  }
  function openRuntime(base, placement, callback) { return _open(base, Lists.copy(placement), "live", callback); }
  function openPreviewView(base, placement, scope, callback) { return _open(base, Lists.copy(placement), "view", callback, scope); }
  function createSettingsEditor(pluginKey, placement, base) {
    if (!base || !base.settingsOwner || !placement) return null;
    var editor = editorFactory.createObject(root, {fields: base.settingsOwner.store.settingsKeys});
    var lifetime = editor._lifetime;
    editor.cancelOpen = _open(base, Lists.copy(placement), "editor", function (result) {
      if (!lifetime.alive || editor.closed) { if (result.editor) result.editor.detach(); return; }
      if (result.status === "opened") editor.attach(result.editor);
      else editor.openError = result.error?.code || "overlay-open";
    });
    return editor;
  }
}
