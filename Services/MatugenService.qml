pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "../Helpers/ColorsConvert.js" as ColorsConvert

Singleton {
  id: root

  readonly property string colorsApplyScript: Quickshell.shellDir + '/Bin/colors-apply.sh'

  property string dynamicConfigPath: Settings.cacheDir + "matugen.dynamic.toml"

  // External state management
  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      // Only detect changes on main screen
      if (screenName === Screen.name && Settings.data.colorSchemes.useWallpaperColors) {
        generateFromWallpaper()
      }
    }
  }

  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      Logger.log("Matugen", "Detected dark mode change")
      if (Settings.data.colorSchemes.useWallpaperColors) {
        MatugenService.generateFromWallpaper()
      }
    }
  }

  // --------------------------------
  function init() {
    // does nothing but ensure the singleton is created
    // do not remove
    Logger.log("Matugen", "Service started")
  }

  // --------------------------------
  // Generate colors using current wallpaper and settings
  function generateFromWallpaper() {
    Logger.log("Matugen", "Generating from wallpaper on screen:", Screen.name)
    var wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")
    if (wp === "") {
      Logger.error("Matugen", "No wallpaper was found")
      return
    }

    var content = MatugenTemplates.buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")

    // Build the main script
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n" + "for d in '" + extraRepo + "' '" + extraUser + "'; do\n" + "  if [ -d \"$d\" ]; then\n" + "    for f in \"$d\"/*.toml; do\n" + "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '" + pathEsc + "'\n" + "    done\n" + "  fi\n"
        + "done\n" + "matugen image '" + wp + "' --config '" + pathEsc + "' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType

    // Add user config execution if enabled
    if (Settings.data.templates.enableUserTemplates) {
      var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
      script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
      script += "  matugen image '" + wp + "' --config '" + userConfigDir + "config.toml' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType + "\n"
      script += "fi"
    }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  // --------------------------------
  function selectVibrantColor(schemeData, mode) {
    var colors = []
    colors.push(schemeData[mode]["mPrimary"]);
    colors.push(schemeData[mode]["mSecondary"]);
    colors.push(schemeData[mode]["mTertiary"]);


    var bestScore = 0
    var bestScoreIndex = -1
    for (var i=0; i<colors.length; i++) {
      var hsl = ColorsConvert.hexToHSL(colors[i])

      var score = hsl['s'];// + hsl['l'];
      if (score > bestScore) {
        bestScore = score
        bestScoreIndex = i
      }
    }

    return colors[bestScoreIndex]
  }

  // --------------------------------
  // Generate templates from predefined color scheme
  function generateFromPredefinedScheme(schemeData) {
    Logger.log("Matugen", "Generating templates from predefined color scheme")

    var content = MatugenTemplates.buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")
    const color = selectVibrantColor(schemeData, mode)

    // Build the script
    var script = ""
    script += "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n\n"
    // script += "for d in '" + extraRepo + "' '" + extraUser + "'; do\n"
    // script += "  if [ -d \"$d\" ]; then\n"
    // script += "    for f in \"$d\"/*.toml; do\n"
    // script += "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '" + pathEsc + "'\n"
    // script += "    done\n"
    // script += "  fi\n"
    // script += "done\n\n"
    script += "matugen color hex '" + color  + "' --config '" + pathEsc + "' --mode " + mode

    console.log(script)

    // // Add user config execution if enabled
    // if (Settings.data.templates.enableUserTemplates) {
    //   var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
    //   script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
    //   script += "  matugen color hex " + color  + " --config '" + userConfigDir + "config.toml' --mode " + mode
    //   script += "fi"
    // }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true

    // -----
    var terminals = {
      foot: "~/.config/foot/themes/noctalia",
      ghostty: "/.config/ghostty/themes/noctalia",
      kitty: "~/.config/kitty/themes/noctalia.conf",
    }

    var copyCmd = Object.entries(terminals)
      .filter(([terminal, colorsPath]) => Settings.data.templates[terminal])
      .map(([terminal, colorsPath]) => {
        // regex matches everything after last '/' in a string
        var colorsPathParent = colorsPath.replace(/[^\/]*$/, "")
        var terminalColorsTemplate = getTerminalColorsTemplate(terminal)
        return [
          // make sure intermediate theme directories are present
          `mkdir -p ${colorsPathParent}`,
          // copy theme file to terminal config directory
          `cp -f ${terminalColorsTemplate} ${colorsPath}`,
          // apply theme config
          `${colorsApplyScript} ${terminal}`,
        ]
      })
      .reduce((arr1, arr2) => arr1.concat(arr2), []) // can't use .flatMap in Qt's environment
      .join("; ")

    if (copyCmd !== "") {
      //console.log(copyCmd)
      copyProcess.command = ["bash", "-lc", copyCmd]
      copyProcess.running = true
    }
  }

  // --------------------------------
  function getTerminalColorsTemplate(terminal) {
    var colorScheme = Settings.data.colorSchemes.predefinedScheme
    const darkLight = Settings.data.colorSchemes.darkMode ? 'dark' : 'light'

    // Convert display names back to folder names
    if (colorScheme === "Noctalia (default)") {
      colorScheme = "Noctalia-default"
    } else if (colorScheme === "Noctalia (legacy)") {
      colorScheme = "Noctalia-legacy"
    } else if (colorScheme === "Tokyo Night") {
      colorScheme = "Tokyo-Night"
    }

    var extension = terminal === 'kitty' ? ".conf" : ""

    return `${Quickshell.shellDir}/Assets/ColorScheme/${colorScheme}/terminal/${terminal}/${colorScheme}-${darkLight}${extension}`
  }

  // --------------------------------
  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          Logger.warn("MatugenService", "GenerateProcess stderr:", this.text)
        }
      }
    }
  }

  // --------------------------------
  Process {
    id: copyProcess
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          Logger.warn("MatugenService", "CopyProcess stderr:", this.text)
        }
      }
    }
  }
}
