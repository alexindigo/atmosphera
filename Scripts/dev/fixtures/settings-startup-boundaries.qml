import QtQuick
import Quickshell
import ConfigQml 1.0
import qs.Commons

// Exercise the actual bootstrap and native file owner, without starting plugins.
ShellRoot {
  id: root
  property int warnings: 0
  property int truncated: 0

  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
      Item {
        SettingsStore {
          id: owner
          legacyFile: SettingsPaths.settingsFile
          overridesDirectory: SettingsPaths.overridesDir.slice(0, -1)
          evidencePath: SettingsPaths.cacheDir + "settings-conflicts"
          homeDirectory: Quickshell.env("HOME")
          defaultFont: "Sans Serif"
          fixedFont: "monospace"
          autoSave: false
          onSourceWarning: warning => {
            root.warnings++;
            if (warning.code === "unknown-setting-truncated")
              root.truncated++;
          }
          onStatusChanged: {
            if (status === ConfigStore.Error) {
              console.error("STARTUP_BOUNDARY_ERROR:", error.code);
              Qt.exit(2);
            } else if (ready) {
              Qt.callLater(function () {
                console.log("STARTUP_BOUNDARY_RESULT:" + JSON.stringify({
                  cache: SettingsPaths.cacheDir,
                  config: SettingsPaths.configDir,
                  state: SettingsPaths.stateDir,
                  settingsFile: SettingsPaths.settingsFile,
                  warnings: root.warnings,
                  truncated: root.truncated,
                  fontScale: owner.values.ui.fontDefaultScale
                }));
                owner.close(function (result) {
                  Qt.exit(result.status === "failed" ? 2 : 0);
                });
              });
            }
          }
        }
      }
    }
  }
  Timer {
    interval: 10000
    running: true
    onTriggered: {
      console.error("STARTUP_BOUNDARY_ERROR: readiness-timeout");
      Qt.exit(2);
    }
  }
}
