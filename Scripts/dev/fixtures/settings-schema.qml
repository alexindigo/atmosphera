import QtQuick
import Quickshell
import ConfigQml 1.0
// The regression runner copies this inert entrypoint to the shell root.
import qs.Commons as Main
import "../../../Helpers/SettingsDefaults.js" as Reference

ShellRoot {
  Main.SettingsSources {
    id: routes
    settingsFile: "/not-opened/legacy.json"
    overridesDirectory: "/not-opened/settings"
  }

  ConfigStore {
    id: store
    schema: Main.SettingsSchema {
      homeDirectory: "/inert/home"
      defaultFont: "Test Sans"
      fixedFont: "Test Mono"
    }
    autoSave: false
    sources: [MemorySource {}]
    onReadyChanged: {
      if (!ready)
        return;
      if (values.settingsVersion !== 62 || values.general.avatarImage !== "/inert/home/.face" || values.wallpaper.directory !== "/inert/home/Pictures/Wallpapers" || values.ui.fontDefault !== "Test Sans" || values.ui.fontFixed !== "Test Mono")
        throw new Error("resolved construction defaults mismatch");
      if (Reference.defaultValue(["settingsVersion"]) !== 0 || Reference.defaultValue(["general", "avatarImage"]) !== "" || !Object.isFrozen(Reference.defaults.bar.widgets.left))
        throw new Error("reference defaults are not immutable/unpatched");
      if (routes.sources.length !== 30 || routes.sources[0].writable || routes.sources.some(function(source) { return source.prefix.indexOf("settingsVersion") !== -1; }))
        throw new Error("source topology mismatch");
      values.bar.widgets.left = [{"id": "Repeated", "pluginPayload": {"arbitrary": [1, false, {"nested": "owned"}]}}, {"id": "Repeated"}];
      if (values.bar.widgets.left.length !== 2 || values.bar.widgets.left[0].pluginPayload.arbitrary[2].nested !== "owned")
        throw new Error("repeat IDs/unknown payload not preserved");
      values.bar.fontScale = 1.25;
      var rejected = 0;
      try { values.bar.widgetSpacing = 2147483648; } catch (error) { rejected++; }
      try { values.wallpaper.fillColor = "not-a-color"; } catch (error) { rejected++; }
      if (rejected !== 2 || values.bar.fontScale !== 1.25 || values.bar.widgetSpacing !== 6 || values.wallpaper.fillColor !== "#000000")
        throw new Error("schema admission mismatch");
      console.log("SETTINGS_SCHEMA_QML: PASS");
      Qt.quit();
    }
  }

  Timer {
    interval: 10000
    running: true
    onTriggered: Qt.exit(1)
  }
}
