pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Assets.Matugen
import qs.Services

Singleton {
  id: root

  property string dynamicConfigPath: Settings.cacheDir + "matugen.dynamic.toml"

  // Build TOML content based on settings
  function buildConfigToml() {
    return Matugen.buildConfigToml()
  }

  // Generate colors using current wallpaper and settings
  function generateFromWallpaper() {
    // Ensure cache dir exists
    Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir])

    Logger.log("Matugen", "Generating from wallpaper on screen:", Screen.name)
    var wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")

    var content = buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")

    // Build the main script
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n" + "for d in '" + extraRepo + "' '" + extraUser
        + "'; do\n" + "  if [ -d \"$d\" ]; then\n"
        + "    for f in \"$d\"/*.toml; do\n" + "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '"
        + pathEsc + "'\n" + "    done\n" + "  fi\n" + "done\n" + "matugen image '" + wp + "' --config '" + pathEsc + "' --mode " + mode

    // Add user config execution if enabled
    if (Settings.data.matugen.enableUserTemplates) {
      var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
      script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
      script += "  matugen image '" + wp + "' --config '" + userConfigDir + "config.toml' --mode " + mode + "\n"
      script += "fi"
    }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false

    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          Logger.warn("MatugenService", "Matugen stderr:", this.text)
        }
      }
    }
  }

  // No separate writer; the write happens inline via bash heredoc
}
