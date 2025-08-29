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

    // TODO: fix matugen
    var content = buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var wp = WallpaperService.currentWallpaper.replace(/'/g, "'\\''")
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n" + "for d in '" + extraRepo + "' '" + extraUser
        + "'; do\n" + "  if [ -d \"$d\" ]; then\n"
        + "    for f in \"$d\"/*.toml; do\n" + "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '"
        + pathEsc + "'\n" + "    done\n" + "  fi\n" + "done\n" + "matugen image '" + wp + "' --config '" + pathEsc + "' --mode " + mode
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stdout: StdioCollector {
      onStreamFinished: Logger.log("Matugen", "Completed colors generation")
    }
    stderr: StdioCollector {
      onStreamFinished: if (this.text !== "")
      Logger.error(this.text)
    }
  }

  // No separate writer; the write happens inline via bash heredoc
}
