pragma Singleton

import QtQuick
import Quickshell
import ConfigQml 1.0
import "../Helpers/SettingsDefaults.js" as Defaults
import "../Helpers/SettingsListCommands.js" as Lists
import "../Helpers/SettingsDraftEditor.js" as DraftEditor
import qs.Commons
import qs.Services.Plugins
import qs.Services.UI

Singleton {
  id: root
  readonly property var data: owner.values
  readonly property alias store: owner
  readonly property int settingsVersion: 62
  readonly property string shellName: SettingsPaths.shellName
  readonly property string configDir: SettingsPaths.configDir
  readonly property string cacheDir: SettingsPaths.cacheDir
  readonly property string stateDir: SettingsPaths.stateDir
  readonly property string settingsFile: SettingsPaths.settingsFile
  readonly property string overridesDir: SettingsPaths.overridesDir
  readonly property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  readonly property string defaultVideosDirectory: Quickshell.env("HOME") + "/Videos"
  readonly property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"
  property bool isDebug: Quickshell.env("ATMOSPHERA_DEBUG") === "1"
  property bool isLoaded: false
  property bool isFreshInstall: false
  property bool shouldOpenSetupWizard: false
  readonly property bool directoriesCreated: owner.ready
  readonly property bool sectionsReady: owner.ready
  property bool _managedBindings: false
  property bool _bindingsUnresolved: false
  property var _groups: Object.create(null)
  property var _groupOrder: []
  property string _acceptedEnvironment: "none"
  property int _resetSerial: 0

  signal settingsLoaded
  signal settingsSaved
  signal settingsSaveFailed(string message)
  signal settingsSaveCompleted(var result)
  signal settingsReloaded
  signal settingExternallyChanged(string path)
  signal bindingsEnvironmentRequested(string environment, string captureToken)
  signal effectiveSettingsChanged(string section)

  SettingsStore {
    id: owner
    legacyFile: root.settingsFile
    overridesDirectory: root.overridesDir.slice(0, -1)
    evidencePath: root.cacheDir + "settings-conflicts"
    homeDirectory: Quickshell.env("HOME")
    defaultFont: Application.font.family
    fixedFont: "monospace"
    onStatusChanged: {
      if (ready && !root.isLoaded) {
        root.isFreshInstall = sourceStates.every(function (state) { return state.presence === "absent"; });
        root.shouldOpenSetupWizard = root.isFreshInstall;
        root.isLoaded = true;
        root.settingsLoaded();
        root.upgradeSettings();
      } else if (status === ConfigStore.Error) {
        Logger.e("Settings", "Settings owner failed:", error);
      }
    }
    onSettingValuesChanged: paths => {
      var sections = Object.create(null);
      for (var path of paths) {
        if (path.length && !sections[path[0]]) {
          sections[path[0]] = true;
          root.effectiveSettingsChanged(path[0]);
        }
      }
    }
    onCompleted: result => {
      if (["save", "autosave", "flush", "close", "saveGroup", "retryGroup", "apply", "overlayApply", "overlayReset", "importProfile"].indexOf(result.operation) === -1 && !(result.operation === "retainGroup" && result.status === "failed"))
        return;
      root.settingsSaveCompleted(result);
      if (result.status === "saved")
        root.settingsSaved();
      else if (result.status === "failed")
        root.settingsSaveFailed(result.error?.code || "settings-save");
    }
    onSourceError: error => Logger.e("Settings", "Source error:", error.code, error.sourceId)
    onSourceWarning: warning => {
      if (warning.code === "unknown-setting") Logger.w("Settings", "Ignoring unknown setting:", warning.path.join("."));
      else Logger.w("Settings", "Source warning:", warning.code, warning.sourceId);
    }
    onSourceAccepted: event => {
      for (var fact of event.facts) {
        if (fact.path.join(".") === "bindings.environment") {
          root._acceptedEnvironment = fact.present ? fact.value : "none";
          if (root.isLoaded && event.origin === "external")
            root.bindingsEnvironmentRequested(root._acceptedEnvironment, "");
        }
      }
      if (root.isLoaded && event.origin === "external") {
        for (var path of event.changedPaths)
          root.settingExternallyChanged(path.join("."));
        root.settingsReloaded();
      }
    }
    onProjectionEffects: event => root._migrationEffects(event.effects)
  }

  Connections {
    target: root.isLoaded ? Service : null
    function onPluginsFullyLoadedChanged() { root.upgradeSettings(); }
    function onPluginLoaded() { root.upgradeSettings(); }
    function onPluginUnloaded() { root.upgradeSettings(); }
  }

  function ensureTrailingSlash(path) { return path.endsWith("/") ? path : path + "/"; }
  function preprocessPath(path) {
    if (typeof path !== "string") return path;
    return path === "~" ? Quickshell.env("HOME") : path.startsWith("~/") ? Quickshell.env("HOME") + path.substring(1) : path;
  }
  function getDefaultValue(path) { return Defaults.defaultValue(typeof path === "string" ? path.split(".") : path); }
  function isValueChanged(path, value) {
    var initial = getDefaultValue(path);
    return initial !== undefined && (typeof value === "object" ? JSON.stringify(value) !== JSON.stringify(initial) : value !== initial);
  }
  function formatDefaultValueForTooltip(path) {
    var value = getDefaultValue(path);
    if (value === undefined) return "";
    if (Array.isArray(value)) return value.length ? "[" + value.length + " items]" : "(empty)";
    if (value !== null && typeof value === "object") return "(object)";
    return value === "" ? "(empty)" : String(value);
  }
  function getPathValue(object, path) {
    var value = object;
    for (var part of (typeof path === "string" ? path.split(".") : path)) {
      if (value === null || value === undefined) return undefined;
      value = value[part];
    }
    return value;
  }
  function isKnownSchemaPath(path) { return owner.info(typeof path === "string" ? path.split(".") : path).declared === true; }
  function setPathValue(object, path, value, prefix) {
    if (!isKnownSchemaPath(prefix ? prefix + "." + path : path)) return false;
    var parts = path.split(".");
    var parent = object;
    for (var i = 0; i < parts.length - 1; ++i) parent = parent[parts[i]];
    parent[parts[parts.length - 1]] = value;
    return true;
  }
  function filePathFor(section) { return section === "legacy" ? settingsFile : overridesDir + section + ".json"; }
  function effectiveDiskEnvironment() { return _acceptedEnvironment; }
  function createRecordListEditor(path, address, additional, options) {
    return Lists.create(owner, path, address, additional, options, function (callback) { Qt.callLater(callback); });
  }
  function createEditor(path) {
    return DraftEditor.create(owner, path, function (callback) { Qt.callLater(callback); });
  }
  function modelIsCurrent(path, model) {
    var info = owner.info(path);
    return Lists.settled(info) && info.publicationGeneration === model.generation;
  }
  function saveImmediate(callback) { return typeof callback === "function" ? owner.save(callback) : owner.save(); }
  function saveResult(callback) { return saveImmediate(callback); }
  function beginManagedBindings() { _managedBindings = true; }
  function setBindingsUnresolved(value) { _bindingsUnresolved = value; }

  // Application request IDs select immutable native captures, not saved values.
  // Only tokens and ordering live here. The worker owns bodies, bases and retries.
  function _dependencies() {
    return _groupOrder.filter(function (token) {
      return ["retained", "stopped", "saving"].indexOf(owner.groupInfo(token).state) !== -1;
    });
  }
  function _saveGroup(token, callback) {
    var state = owner.groupInfo(token).state;
    return state === "stopped" ? owner.retryGroup(token, callback) : owner.saveGroup(token, callback);
  }
  function _retain(key, paths, edits, callback) {
    if (_groups[key]) return _saveGroup(_groups[key], callback);
    return owner.retainGroup({requestKey: key, paths: paths, edits: edits, dependencies: _dependencies()}, function (result) {
      if (result.status !== "retained") {
        if (typeof callback === "function") callback(result);
        return;
      }
      root._groups[key] = result.groupToken;
      root._groupOrder.push(result.groupToken);
      root._saveGroup(result.groupToken, callback);
    });
  }
  function saveBindingsEnvironment(environment, callback, identity, captureToken) {
    if (captureToken) {
      _groups[identity] = captureToken;
      return _saveGroup(captureToken, callback);
    }
    return _retain(identity, [["bindings"]], [{path: ["bindings", "environment"], present: true, value: environment}], callback);
  }
  function saveSetupWork(work, callback, identity) {
    // Invalid application IDs still enter the native ordered completion queue.
    if (!identity) {
      owner.saveGroup("", callback);
      return false;
    }
    return _retain(identity + ":setup", [["general", "scaleRatio"], ["bar", "position"], ["wallpaper", "directory"], ["colorSchemes"], ["dock"]], [
      {path: ["general", "scaleRatio"], present: true, value: work.scaleRatio},
      {path: ["bar", "position"], present: true, value: work.barPosition},
      {path: ["wallpaper", "directory"], present: true, value: work.wallpaperDirectory}
    ], callback);
  }
  function releaseManagedRequest(identity) {
    for (var key of [identity, identity + ":setup"]) {
      var token = _groups[key];
      if (token && owner.groupInfo(token).state === "succeeded") {
        owner.releaseGroup(token);
        _groupOrder = _groupOrder.filter(function (value) { return value !== token; });
      }
    }
  }
  function _reset(path) {
    if (_managedBindings && path[0] === "bindings") {
      owner.retainGroup({requestKey: "bindings-reset-" + (++_resetSerial), paths: [["bindings"]], edits: [{path: path, present: false}], dependencies: _dependencies()}, function (result) {
        if (result.status === "retained") {
          root._groupOrder.push(result.groupToken);
          root.bindingsEnvironmentRequested(root.data.bindings.environment, result.groupToken);
        }
      });
      return;
    }
    owner.reset(path, "user");
    owner.save();
  }
  function resetSection(key) { _reset([key]); }
  function resetValue(path) { _reset(path.split(".")); }

  function _findScreenOverride(screenName) {
    var overrides = data.bar.screenOverrides;
    if (!overrides) return null;
    for (var i = 0; screenName && i < overrides.length; ++i)
      if (overrides[i] && overrides[i].name === screenName) return overrides[i];
    return null;
  }
  function _findScreenOverrideIndex(screenName) {
    var overrides = data.bar.screenOverrides;
    if (!overrides) return -1;
    for (var i = 0; screenName && i < overrides.length; ++i)
      if (overrides[i] && overrides[i].name === screenName) return i;
    return -1;
  }
  function isScreenOverrideEnabled(screenName) { var row = _findScreenOverride(screenName); return !!row && row.enabled !== false; }
  function getBarPositionForScreen(screenName) {
    var row = _findScreenOverride(screenName);
    return row && row.enabled !== false && row.position !== undefined ? row.position : data.bar.position || "top";
  }
  function getBarWidgetsForScreen(screenName) {
    var row = _findScreenOverride(screenName);
    return row && row.enabled !== false && row.widgets !== undefined ? row.widgets : data.bar.widgets;
  }
  function getBarDensityForScreen(screenName) {
    var row = _findScreenOverride(screenName);
    return row && row.enabled !== false && row.density !== undefined ? row.density : data.bar.density || "default";
  }
  function getBarDisplayModeForScreen(screenName) {
    var row = _findScreenOverride(screenName);
    return row && row.enabled !== false && row.displayMode !== undefined ? row.displayMode : data.bar.displayMode || "always_visible";
  }
  function hasScreenOverride(screenName, property) {
    var row = _findScreenOverride(screenName);
    return !!row && (property ? Object.prototype.hasOwnProperty.call(row, property) : Object.keys(row).some(function (key) { return key !== "name"; }));
  }
  function getScreenOverrideEntry(screenName) { return _findScreenOverride(screenName); }
  function setScreenOverride(screenName, field, value) {
    if (!screenName || typeof field !== "string" || !field) return false;
    var editor = createRecordListEditor(["bar", "screenOverrides"], []);
    if (!editor) return false;
    var index = editor.initialValue.findIndex(function (row) { return row.name === screenName; });
    var edit;
    if (index === -1) {
      var row = Object.create(null);
      row.name = screenName;
      row[field] = value;
      edit = {op: "insert", index: editor.initialValue.length, value: row};
    } else edit = {op: "set", index: index, field: field, value: value};
    return editor.submit([edit], function () { editor.detach(); });
  }
  function clearScreenOverride(screenName, field) {
    var editor = createRecordListEditor(["bar", "screenOverrides"], []);
    if (!editor) return false;
    var index = editor.initialValue.findIndex(function (row) { return row.name === screenName; });
    if (index === -1) { editor.detach(); return false; }
    var remaining = Object.keys(editor.initialValue[index]).filter(function (key) { return key !== field && key !== "name"; });
    var edit = !field || remaining.length === 0 ? {op: "remove", index: index} : {op: "unset", index: index, field: field};
    return editor.submit([edit], function () { editor.detach(); });
  }

  function upgradeSettings() {
    if (!isLoaded || !Service.initialized || !Service.pluginsFullyLoaded || !BarWidgetRegistry.widgets || Object.keys(BarWidgetRegistry.widgets).length === 0) return;
    function entries(registry, normalize, retainInstalled) {
      var ids = Object.keys(registry.widgets);
      // Installed but unloadable bar plugins remain visible placeholders.
      if (retainInstalled) {
        for (var plugin of Object.keys(Registry.installedPlugins)) {
          var id = "plugin:" + plugin;
          if (ids.indexOf(id) === -1 && Registry.isPluginDownloaded(plugin)) ids.push(id);
        }
      }
      return ids.map(function (key) {
        return {key: key, available: registry.hasWidget(key), retain: retainInstalled && key.startsWith("plugin:") && Registry.isPluginDownloaded(key.substring(7)), normalize: normalize && registry.widgetMetadata[key] !== undefined, defaults: normalize ? registry.widgetMetadata[key] || {} : {}};
      });
    }
    var bar = {ready: true, entries: entries(BarWidgetRegistry, true, true)};
    var shortcuts = {ready: true, entries: entries(ControlCenterWidgetRegistry, false, false)};
    var desktop = {ready: true, entries: entries(DesktopWidgetRegistry, false, false)};
    for (var section of ["left", "center", "right"]) owner.updateRecordListPolicy("bar-" + section, bar);
    for (var section of ["left", "right"]) owner.updateRecordListPolicy("shortcuts-" + section, shortcuts);
    owner.updateRecordListPolicy("desktop-widgets", desktop);
  }
  function _migrationEffects(effects) {
    // Only the historical six shell-effect wrappers remain production code.
    // Their effect execution is not, and never was, a settings save receipt.
    var actions = {
      "clear-emoji-usage": 36, "create-legacy-pam": 44,
      "remove-legacy-pam": 46, "clear-network-stats": 47,
      "clear-launcher-usage": 49, "migrate-color-schemes": 56
    };
    for (var effect of effects) {
      if (actions[effect.action] !== effect.version) {
        Logger.e("Settings", "Unknown migration effect");
        continue;
      }
      var component = Qt.createComponent(Qt.resolvedUrl("Migrations/Migration" + effect.version + ".qml"));
      var migration = component.status === Component.Ready ? component.createObject(root) : null;
      if (!migration) Logger.e("Settings", "Migration effect unavailable:", effect.version);
      else {
        migration.migrate(null, Logger, null);
        migration.destroy();
      }
    }
  }
}
