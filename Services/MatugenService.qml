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
    // Use a unique delimiter to avoid conflicts with config content
    var delimiter = "MATUGEN_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9)
    var script = "cat > '" + pathEsc + "' << '" + delimiter + "'\n" + content + "\n" + delimiter + "\n"

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

    // Use the full predefined color scheme instead of generating from a single color
    var script = buildPredefinedSchemeScriptWithFullColors(content, pathEsc, schemeData, mode)
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  // --------------------------------
  function buildPredefinedSchemeScriptWithFullColors(content, pathEsc, schemeData, mode) {
    // Instead of using matugen color generation, directly process templates with predefined colors
    var colors = schemeData[mode] || schemeData.dark || schemeData.light
    var script = ""

    // Process each enabled template directly with predefined colors
    script += processTemplatesWithPredefinedColors(colors, mode)

    // Add user template execution if enabled
    script += addUserTemplateExecutionForPredefinedColors(colors, mode)

    return script
  }

  // --------------------------------
  function processTemplatesWithPredefinedColors(colors, mode) {
    var script = ""

    // Create a colors object that matches matugen's expected format
    var matugenColors = {
      "primary": {
        "default": {
          "hex": colors.mPrimary
        }
      },
      "on_primary": {
        "default": {
          "hex": colors.mOnPrimary
        }
      },
      "primary_container": {
        "default": {
          "hex": colors.mPrimary
        }
      },
      "on_primary_container": {
        "default": {
          "hex": colors.mOnPrimary
        }
      },
      "secondary": {
        "default": {
          "hex": colors.mSecondary
        }
      },
      "on_secondary": {
        "default": {
          "hex": colors.mOnSecondary
        }
      },
      "secondary_container": {
        "default": {
          "hex": colors.mSecondary
        }
      },
      "on_secondary_container": {
        "default": {
          "hex": colors.mOnSecondary
        }
      },
      "tertiary": {
        "default": {
          "hex": colors.mTertiary
        }
      },
      "on_tertiary": {
        "default": {
          "hex": colors.mOnTertiary
        }
      },
      "tertiary_container": {
        "default": {
          "hex": colors.mTertiary
        }
      },
      "on_tertiary_container": {
        "default": {
          "hex": colors.mOnTertiary
        }
      },
      "error": {
        "default": {
          "hex": colors.mError
        }
      },
      "on_error": {
        "default": {
          "hex": colors.mOnError
        }
      },
      "error_container": {
        "default": {
          "hex": colors.mError
        }
      },
      "on_error_container": {
        "default": {
          "hex": colors.mOnError
        }
      },
      "background": {
        "default": {
          "hex": colors.mSurface
        }
      },
      "on_background": {
        "default": {
          "hex": colors.mOnSurface
        }
      },
      "surface": {
        "default": {
          "hex": colors.mSurface
        }
      },
      "on_surface": {
        "default": {
          "hex": colors.mOnSurface
        }
      },
      "surface_variant": {
        "default": {
          "hex": colors.mSurfaceVariant
        }
      },
      "on_surface_variant": {
        "default": {
          "hex": colors.mOnSurfaceVariant
        }
      },
      "outline": {
        "default": {
          "hex": colors.mOutline
        }
      },
      "outline_variant": {
        "default": {
          "hex": colors.mOutline
        }
      },
      "shadow": {
        "default": {
          "hex": colors.mShadow
        }
      },
      "surface_container": {
        "default": {
          "hex": colors.mSurfaceVariant
        }
      },
      "surface_container_low": {
        "default": {
          "hex": colors.mSurface
        }
      },
      "surface_container_lowest": {
        "default": {
          "hex": colors.mSurface
        }
      },
      "surface_container_high": {
        "default": {
          "hex": colors.mSurfaceVariant
        }
      },
      "surface_container_highest": {
        "default": {
          "hex": colors.mOutline
        }
      }
    }

    // Process each enabled template using the same structure as MatugenTemplates
    var applications = [{
                          "name": "gtk",
                          "templates": [{
                              "version": "gtk3",
                              "output": "gtk3"
                            }, {
                              "version": "gtk4",
                              "output": "gtk4"
                            }],
                          "input": "gtk.css"
                        }, {
                          "name": "qt",
                          "templates": [{
                              "version": "qt5",
                              "output": "qt5"
                            }, {
                              "version": "qt6",
                              "output": "qt6"
                            }],
                          "input": "qtct.conf"
                        }, {
                          "name": "fuzzel",
                          "templates": [{
                              "version": "fuzzel",
                              "output": "fuzzel"
                            }],
                          "input": "fuzzel.conf"
                        }, {
                          "name": "pywalfox",
                          "templates": [{
                              "version": "pywalfox",
                              "output": "pywalfox"
                            }],
                          "input": "pywalfox.json"
                        }, {
                          "name": "vesktop",
                          "templates": [{
                              "version": "vesktop",
                              "output": "vesktop"
                            }],
                          "input": "vesktop.css"
                        }]

    applications.forEach(function (app) {
      if (Settings.data.templates[app.name]) {
        script += processTemplateForApp(app.name, matugenColors, mode)
      }
    })

    return script
  }

  // --------------------------------
  function processTemplateForApp(appName, colors, mode) {
    var script = ""

    switch (appName) {
    case "gtk":
      script += processGtkTemplate(colors, mode)
      break
    case "qt":
      script += processQtTemplate(colors, mode)
      break
    case "fuzzel":
      script += processFuzzelTemplate(colors, mode)
      break
    case "pywalfox":
      script += processPywalfoxTemplate(colors, mode)
      break
    case "vesktop":
      script += processVesktopTemplate(colors, mode)
      break
    }

    return script
  }

  // --------------------------------
  function processGtkTemplate(colors, mode) {
    var script = ""
    var templatePath = Quickshell.shellDir + "/Assets/MatugenTemplates/gtk.css"
    var homeDir = Quickshell.env("HOME")
    var outputPath3 = homeDir + "/.config/gtk-3.0/gtk.css"
    var outputPath4 = homeDir + "/.config/gtk-4.0/gtk.css"

    // Process GTK3 template
    script += "mkdir -p " + homeDir + "/.config/gtk-3.0\n"
    script += "cp '" + templatePath + "' '" + outputPath3 + "'\n"
    script += replaceColorsInFile(outputPath3, colors)

    // Process GTK4 template
    script += "mkdir -p " + homeDir + "/.config/gtk-4.0\n"
    script += "cp '" + templatePath + "' '" + outputPath4 + "'\n"
    script += replaceColorsInFile(outputPath4, colors)

    script += "gsettings set org.gnome.desktop.interface color-scheme prefer-" + mode + "\n"

    return script
  }

  // --------------------------------
  function processQtTemplate(colors, mode) {
    var script = ""
    var templatePath = Quickshell.shellDir + "/Assets/MatugenTemplates/qtct.conf"
    var homeDir = Quickshell.env("HOME")
    var outputPath5 = homeDir + "/.config/qt5ct/colors/noctalia.conf"
    var outputPath6 = homeDir + "/.config/qt6ct/colors/noctalia.conf"

    // Process Qt5 template
    script += "mkdir -p " + homeDir + "/.config/qt5ct/colors\n"
    script += "cp '" + templatePath + "' '" + outputPath5 + "'\n"
    script += replaceColorsInFile(outputPath5, colors)

    // Process Qt6 template
    script += "mkdir -p " + homeDir + "/.config/qt6ct/colors\n"
    script += "cp '" + templatePath + "' '" + outputPath6 + "'\n"
    script += replaceColorsInFile(outputPath6, colors)

    return script
  }

  // --------------------------------
  function processFuzzelTemplate(colors, mode) {
    var script = ""
    var templatePath = Quickshell.shellDir + "/Assets/MatugenTemplates/fuzzel.conf"
    var homeDir = Quickshell.env("HOME")
    var outputPath = homeDir + "/.config/fuzzel/themes/noctalia"

    script += "mkdir -p " + homeDir + "/.config/fuzzel/themes\n"
    script += "cp '" + templatePath + "' '" + outputPath + "'\n"
    script += replaceColorsInFile(outputPath, colors)
    script += MatugenService.colorsApplyScript + " fuzzel\n"

    return script
  }

  // --------------------------------
  function processPywalfoxTemplate(colors, mode) {
    var script = ""
    var templatePath = Quickshell.shellDir + "/Assets/MatugenTemplates/pywalfox.json"
    var homeDir = Quickshell.env("HOME")
    var outputPath = homeDir + "/.cache/wal/colors.json"

    script += "mkdir -p " + homeDir + "/.cache/wal\n"
    script += "cp '" + templatePath + "' '" + outputPath + "'\n"
    script += replaceColorsInFile(outputPath, colors)
    script += MatugenService.colorsApplyScript + " pywalfox\n"

    return script
  }

  // --------------------------------
  function processVesktopTemplate(colors, mode) {
    var script = ""
    var templatePath = Quickshell.shellDir + "/Assets/MatugenTemplates/vesktop.css"
    var homeDir = Quickshell.env("HOME")
    var outputPath = homeDir + "/.config/vesktop/themes/noctalia.theme.css"

    script += "mkdir -p " + homeDir + "/.config/vesktop/themes\n"
    script += "cp '" + templatePath + "' '" + outputPath + "'\n"
    script += replaceColorsInFile(outputPath, colors)

    return script
  }

  // --------------------------------
  function replaceColorsInFile(filePath, colors) {
    var script = ""

    // Replace all color placeholders with actual colors
    Object.keys(colors).forEach(function (colorKey) {
      var colorValue = colors[colorKey].default.hex
      // Escape special characters in the color value for sed
      var escapedColor = colorValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      script += "sed -i 's/{{colors\\." + colorKey + "\\.default\\.hex}}/" + escapedColor + "/g' '" + filePath + "'\n"
    })

    return script
  }

  // --------------------------------
  function addUserTemplateExecutionForPredefinedColors(colors, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    var userConfigPath = getUserConfigPath()
    var script = "\n# Execute user config if it exists\n"
    script += "if [ -f '" + userConfigPath + "' ]; then\n"
    script += "  # Process user templates with predefined colors\n"
    script += "  echo 'User templates processing not implemented for predefined colors yet'\n"
    script += "fi"

    return script
  }

  // --------------------------------
  function buildPredefinedSchemeScript(content, pathEsc, color, mode) {
    // Use a unique delimiter to avoid conflicts with config content
    var delimiter = "MATUGEN_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9)
    var script = "cat > '" + pathEsc + "' << '" + delimiter + "'\n" + content + "\n" + delimiter + "\n\n"
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
