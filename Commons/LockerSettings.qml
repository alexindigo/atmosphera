pragma Singleton
import ConfigQml 1.0

import QtQuick
import Quickshell
import "../Helpers/SettingsDefaults.js" as Defaults
import qs.Commons
import qs.Services.Locker

// Installed as the bundled config's qs.Commons.Settings. The shell's Settings
// singleton remains the sole writer; this facade exposes native read-only data.
Singleton {
  id: root
  readonly property bool readOnly: true
  readonly property bool managed: !!Quickshell.env("ATMOSPHERA_LOCK_GENERATION") && !!Quickshell.env("ATMOSPHERA_LOCK_ADAPTER")
  readonly property var store: reader.item
  readonly property var data: store ? store.values : defaults.values
  readonly property bool isLoaded: store ? store.ready : false
  readonly property bool directoriesCreated: isLoaded
  readonly property bool sectionsReady: isLoaded
  readonly property bool isDebug: Quickshell.env("ATMOSPHERA_DEBUG") === "1"
  readonly property string shellName: SettingsPaths.shellName
  readonly property string configDir: SettingsPaths.configDir
  readonly property string cacheDir: SettingsPaths.cacheDir
  readonly property string stateDir: SettingsPaths.stateDir
  readonly property string settingsFile: SettingsPaths.settingsFile
  readonly property string overridesDir: SettingsPaths.overridesDir
  readonly property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  readonly property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"
  property bool _loaded: false

  signal settingsLoaded
  signal settingsReloaded
  signal effectiveSettingsChanged(string section)
  signal settingExternallyChanged(string path)

  ConfigStore {
    id: defaults
    autoSave: false
    schema: SettingsSchema {
      homeDirectory: Quickshell.env("HOME")
      defaultFont: Application.font.family
      fixedFont: "monospace"
    }
  }
  Loader {
    id: reader
    sourceComponent: root.managed ? published : standalone
  }
  Component {
    id: published
    LockSettingsStore {
      viewPath: Quickshell.env("ATMOSPHERA_LOCK_SETTINGS_FILE")
      session: Quickshell.env("ATMOSPHERA_LOCK_SESSION")
      generation: Quickshell.env("ATMOSPHERA_LOCK_GENERATION")
    }
  }
  Component {
    id: standalone
    SettingsStore {
      readOnly: true
      legacyFile: root.settingsFile
      overridesDirectory: root.overridesDir.slice(0, -1)
      evidencePath: root.cacheDir + "settings-conflicts"
      homeDirectory: Quickshell.env("HOME")
      defaultFont: Application.font.family
      fixedFont: "monospace"
      // This consumer deliberately does not execute projectionEffects.
      // Legacy compatibility is a nonpersistent view; raw schema version is 0.
    }
  }
  onIsLoadedChanged: {
    if (isLoaded && !_loaded) {
      _loaded = true;
      settingsLoaded();
    }
  }
  Connections {
    target: root.store
    function onSettingValuesChanged(paths) {
      if (!root._loaded)
        return;
      var sections = Object.create(null);
      for (var path of paths) {
        if (path.length)
          sections[path[0]] = true;
        root.settingExternallyChanged(path.join("."));
      }
      for (var section of Object.keys(sections))
        root.effectiveSettingsChanged(section);
      root.settingsReloaded();
    }
  }

  function ensureTrailingSlash(path) {
    return path.endsWith("/") ? path : path + "/";
  }
  function preprocessPath(path) {
    if (typeof path !== "string")
      return path;
    return path === "~" ? Quickshell.env("HOME") : path.startsWith("~/") ? Quickshell.env("HOME") + path.substring(1) : path;
  }
  function getDefaultValue(path) {
    return Defaults.defaultValue(typeof path === "string" ? path.split(".") : path);
  }
  function _screenOverride(name) {
    var rows = data.bar.screenOverrides;
    if (!rows)
      return null;
    for (var i = 0; name && i < rows.length; ++i)
      if (rows[i] && rows[i].name === name)
        return rows[i];
    return null;
  }
  function getBarPositionForScreen(name) {
    var row = _screenOverride(name);
    return row && row.position !== undefined ? row.position : data.bar.position || "top";
  }
  function getBarDensityForScreen(name) {
    var row = _screenOverride(name);
    return row && row.density !== undefined ? row.density : data.bar.density || "default";
  }
}
