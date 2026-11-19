pragma Singleton
import Quickshell

// Pure path metadata, safe before construction of any settings/service graph.
Singleton {
  readonly property string shellName: "atmosphera"
  readonly property string configDir: slash(Quickshell.env("ATMOSPHERA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName)
  readonly property string cacheDir: slash(Quickshell.env("ATMOSPHERA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName)
  readonly property string stateDir: slash(Quickshell.env("ATMOSPHERA_STATE_DIR") || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/" + shellName)
  readonly property string settingsFile: absolute(Quickshell.env("ATMOSPHERA_SETTINGS_FILE") || configDir + "settings.json")
  readonly property string overridesDir: configDir + "settings/"
  // File owners require clean absolute filesystem paths, not URL resolution.
  // Resolve all overrides at this shared boundary so bootstrap and owners agree.
  function absolute(path) {
    var parts = (path.startsWith("/") ? path : Quickshell.workingDirectory + "/" + path).split("/");
    var clean = [];
    for (var part of parts) {
      if (part === "..")
        clean.pop();
      else if (part !== "" && part !== ".")
        clean.push(part);
    }
    return "/" + clean.join("/");
  }
  function slash(path) {
    var clean = absolute(path);
    return clean.endsWith("/") ? clean : clean + "/";
  }
}
