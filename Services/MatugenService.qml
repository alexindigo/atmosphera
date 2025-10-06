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
    if (content === "") {
      return
    }

    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var script = buildMatugenScript(content, pathEsc, wp, mode)
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  // --------------------------------
  function buildMatugenScript(content, pathEsc, wallpaper, mode) {
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n"

    // Main matugen command
    script += "matugen image '" + wallpaper + "' --config '" + pathEsc + "' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType

    // Add user template execution if enabled
    script += addUserTemplateExecution(wallpaper, mode)

    return script + "\n"
  }

  // --------------------------------
  function addUserTemplateExecution(input, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    var userConfigPath = getUserConfigPath()
    var script = "\n# Execute user config if it exists\n"
    script += "if [ -f '" + userConfigPath + "' ]; then\n"
    script += "  matugen image '" + input + "' --config '" + userConfigPath + "' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType + "\n"
    script += "fi"

    return script
  }

  // --------------------------------
  function getUserConfigPath() {
    return (Quickshell.env("HOME") + "/.config/matugen/config.toml").replace(/'/g, "'\\''")
  }

  // --------------------------------
  function selectVibrantColor(schemeData, mode) {
    var colors = []
    colors.push(schemeData[mode]["mPrimary"])
    colors.push(schemeData[mode]["mSecondary"])
    colors.push(schemeData[mode]["mTertiary"])

    var bestScore = 0
    var bestScoreIndex = -1
    for (var i = 0; i < colors.length; i++) {
      var hsl = ColorsConvert.hexToHSL(colors[i])

      var score = hsl['s']
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

    // Handle terminal theme copying for predefined schemes
    handleTerminalThemes()

    var content = MatugenTemplates.buildConfigToml()
    if (content === "") {
      return
    }

    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    const color = selectVibrantColor(schemeData, mode)
    var script = buildPredefinedSchemeScript(content, pathEsc, color, mode)
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  // --------------------------------
  function buildPredefinedSchemeScript(content, pathEsc, color, mode) {
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n\n"
    script += "matugen color hex '" + color + "' --config '" + pathEsc + "' --mode " + mode + "\n"

    // Add user template execution if enabled
    script += addUserTemplateExecutionForColor(color, mode)

    return script
  }

  // --------------------------------
  function addUserTemplateExecutionForColor(color, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    var userConfigPath = getUserConfigPath()
    var script = "\n# Execute user config if it exists\n"
    script += "if [ -f '" + userConfigPath + "' ]; then\n"
    script += "  matugen color hex '" + color + "' --config '" + userConfigPath + "' --mode " + mode + "\n"
    script += "fi"

    return script
  }

  // --------------------------------
  function handleTerminalThemes() {
    var terminals = {
      "foot": "~/.config/foot/themes/noctalia",
      "ghostty": "~/.config/ghostty/themes/noctalia",
      "kitty": "~/.config/kitty/themes/noctalia.conf"
    }

    var copyCmd = Object.keys(terminals).filter(function (terminal) {
      return Settings.data.templates[terminal]
    }).map(function (terminal) {
      var colorsPath = terminals[terminal]
      var colorsPathParent = colorsPath.replace(/[^\/]*$/, "")
      var terminalColorsTemplate = getTerminalColorsTemplate(terminal)
      return ['mkdir -p ' + colorsPathParent, 'cp -f ' + terminalColorsTemplate + ' ' + colorsPath, colorsApplyScript + ' ' + terminal]
    }).reduce(function (arr1, arr2) {
      return arr1.concat(arr2)
    }, []).join('; ')

    if (copyCmd !== "") {
      copyProcess.command = ["bash", "-lc", copyCmd]
      copyProcess.running = true
    }
  }

  // --------------------------------
  function getTerminalColorsTemplate(terminal) {
    var colorScheme = Settings.data.colorSchemes.predefinedScheme
    const darkLight = Settings.data.colorSchemes.darkMode ? 'dark' : 'light'

    // Convert display names back to folder names
    var schemeMap = {
      "Noctalia (default)": "Noctalia-default",
      "Noctalia (legacy)": "Noctalia-legacy",
      "Tokyo Night": "Tokyo-Night"
    }

    colorScheme = schemeMap[colorScheme] || colorScheme
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
