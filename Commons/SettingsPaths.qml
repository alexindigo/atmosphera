pragma Singleton
import Quickshell

// Pure path metadata, safe before construction of any settings/service graph.
Singleton {
  readonly property string shellName: "atmosphera"
  readonly property string configDir: slash(Quickshell.env("ATMOSPHERA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName)
  readonly property string cacheDir: slash(Quickshell.env("ATMOSPHERA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName)
  readonly property string stateDir: slash(Quickshell.env("ATMOSPHERA_STATE_DIR") || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/" + shellName)
  readonly property string settingsFile: Quickshell.env("ATMOSPHERA_SETTINGS_FILE") || configDir + "settings.json"
  readonly property string overridesDir: configDir + "settings/"
  function slash(path) { return path.endsWith("/") ? path : path + "/"; }
}
