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
  readonly property string dynamicConfigPath: Settings.cacheDir + "matugen.dynamic.toml"

  readonly property var templateConfigs: ({
                                            "gtk": {
                                              "input": "gtk.css",
                                              "outputs": [{
                                                  "path": "~/.config/gtk-3.0/gtk.css"
                                                }, {
                                                  "path": "~/.config/gtk-4.0/gtk.css"
                                                }],
                                              "postProcess": mode => `gsettings set org.gnome.desktop.interface color-scheme prefer-${mode}\n`
                                            },
                                            "qt": {
                                              "input": "qtct.conf",
                                              "outputs": [{
                                                  "path": "~/.config/qt5ct/colors/noctalia.conf"
                                                }, {
                                                  "path": "~/.config/qt6ct/colors/noctalia.conf"
                                                }]
                                            },
                                            "fuzzel": {
                                              "input": "fuzzel.conf",
                                              "outputs": [{
                                                  "path": "~/.config/fuzzel/themes/noctalia"
                                                }],
                                              "postProcess": () => `${colorsApplyScript} fuzzel\n`
                                            },
                                            "pywalfox": {
                                              "input": "pywalfox.json",
                                              "outputs": [{
                                                  "path": "~/.cache/wal/colors.json"
                                                }],
                                              "postProcess": () => `${colorsApplyScript} pywalfox\n`
                                            },
                                            "vesktop": {
                                              "input": "vesktop.css",
                                              "outputs": [{
                                                  "path": "~/.config/vesktop/themes/noctalia.theme.css"
                                                }]
                                            }
                                          })

  readonly property var terminalPaths: ({
                                          "foot": "~/.config/foot/themes/noctalia",
                                          "ghostty": "~/.config/ghostty/themes/noctalia",
                                          "kitty": "~/.config/kitty/themes/noctalia.conf"
                                        })

  readonly property var schemeNameMap: ({
                                          "Noctalia (default)": "Noctalia-default",
                                          "Noctalia (legacy)": "Noctalia-legacy",
                                          "Tokyo Night": "Tokyo-Night"
                                        })

  // ===== Lifecycle =====
  function init() {
    Logger.log("Matugen", "Service started")
  }

  // ===== External Connections =====
  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
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
        generateFromWallpaper()
      }
    }
  }

  // ===== Wallpaper Generation =====
  function generateFromWallpaper() {
    Logger.log("Matugen", "Generating from wallpaper on screen:", Screen.name)

    const wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")
    if (!wp) {
      Logger.error("Matugen", "No wallpaper found")
      return
    }

    const content = MatugenTemplates.buildConfigToml()
    if (!content)
      return

    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    const script = buildMatugenScript(content, wp, mode)

    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  function buildMatugenScript(content, wallpaper, mode) {
    const delimiter = "MATUGEN_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9)
    const pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")

    let script = `cat > '${pathEsc}' << '${delimiter}'\n${content}\n${delimiter}\n`
    script += `matugen image '${wallpaper}' --config '${pathEsc}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}`
    script += buildUserTemplateCommand(wallpaper, mode)

    return script + "\n"
  }

  // ===== Predefined Scheme Generation =====
  function generateFromPredefinedScheme(schemeData) {
    Logger.log("Matugen", "Generating templates from predefined color scheme")

    handleTerminalThemes()

    const mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    const colors = schemeData[mode] || schemeData.dark || schemeData.light
    const matugenColors = buildMatugenColorObject(colors)

    const script = processAllTemplates(matugenColors, mode)

    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  function buildMatugenColorObject(colors) {
    // Helper with fallback support
    const c = (color, fallback) => ({
                                      "default": {
                                        "hex": colors[color] || colors[fallback] || "#000000"
                                      }
                                    })

    return {
      "primary": c("mPrimary"),
      "on_primary": c("mOnPrimary"),
      "primary_container": c("mPrimaryContainer", "mPrimary"),
      "on_primary_container": c("mOnPrimaryContainer", "mOnPrimary"),
      "secondary": c("mSecondary"),
      "on_secondary": c("mOnSecondary"),
      "secondary_container": c("mSecondaryContainer", "mSecondary"),
      "on_secondary_container": c("mOnSecondaryContainer", "mOnSecondary"),
      "tertiary": c("mTertiary"),
      "on_tertiary": c("mOnTertiary"),
      "tertiary_container": c("mTertiaryContainer", "mTertiary"),
      "on_tertiary_container": c("mOnTertiaryContainer", "mOnTertiary"),
      "error": c("mError"),
      "on_error": c("mOnError"),
      "error_container": c("mErrorContainer", "mError"),
      "on_error_container": c("mOnErrorContainer", "mOnError"),
      "background": c("mBackground", "mSurface"),
      "on_background": c("mOnBackground", "mOnSurface"),
      "surface": c("mSurface"),
      "on_surface": c("mOnSurface"),
      "surface_variant": c("mSurfaceVariant", "mSurface"),
      "on_surface_variant": c("mOnSurfaceVariant", "mOnSurface"),
      "surface_container_lowest": c("mSurfaceContainerLowest", "mSurface"),
      "surface_container_low": c("mSurfaceContainerLow", "mSurface"),
      "surface_container": c("mSurfaceContainer", "mSurfaceVariant"),
      "surface_container_high": c("mSurfaceContainerHigh", "mSurfaceVariant"),
      "surface_container_highest": c("mSurfaceContainerHighest", "mOutline"),
      "outline": c("mOutline"),
      "outline_variant": c("mOutlineVariant", "mOutline"),
      "shadow": c("mShadow")
    }
  }

  function processAllTemplates(colors, mode) {
    let script = ""
    const homeDir = Quickshell.env("HOME")

    Object.keys(templateConfigs).forEach(appName => {
                                           if (Settings.data.templates[appName]) {
                                             script += processTemplate(appName, colors, mode, homeDir)
                                           }
                                         })

    return script
  }

  function processTemplate(appName, colors, mode, homeDir) {
    const config = templateConfigs[appName]
    const templatePath = `${Quickshell.shellDir}/Assets/MatugenTemplates/${config.input}`
    let script = ""

    config.outputs.forEach(output => {
                             const outputPath = output.path.replace("~", homeDir)
                             const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'))

                             script += `mkdir -p ${outputDir}\n`
                             script += `cp '${templatePath}' '${outputPath}'\n`
                             script += replaceColorsInFile(outputPath, colors)
                           })

    if (config.postProcess) {
      script += config.postProcess(mode)
    }

    return script
  }

  function replaceColorsInFile(filePath, colors) {
    let script = ""
    Object.keys(colors).forEach(colorKey => {
                                  const colorValue = colors[colorKey].default.hex
                                  const escapedColor = colorValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                                  script += `sed -i 's/{{colors\\.${colorKey}\\.default\\.hex}}/${escapedColor}/g' '${filePath}'\n`
                                })
    return script
  }

  // ===== Terminal Themes =====
  function handleTerminalThemes() {
    const commands = []

    Object.keys(terminalPaths).forEach(terminal => {
                                         if (Settings.data.templates[terminal]) {
                                           const outputPath = terminalPaths[terminal]
                                           const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'))
                                           const templatePath = getTerminalColorsTemplate(terminal)

                                           commands.push(`mkdir -p ${outputDir}`)
                                           commands.push(`cp -f ${templatePath} ${outputPath}`)
                                           commands.push(`${colorsApplyScript} ${terminal}`)
                                         }
                                       })

    if (commands.length > 0) {
      copyProcess.command = ["bash", "-lc", commands.join('; ')]
      copyProcess.running = true
    }
  }

  function getTerminalColorsTemplate(terminal) {
    let colorScheme = Settings.data.colorSchemes.predefinedScheme
    const mode = Settings.data.colorSchemes.darkMode ? 'dark' : 'light'

    colorScheme = schemeNameMap[colorScheme] || colorScheme
    const extension = terminal === 'kitty' ? ".conf" : ""

    return `${Quickshell.shellDir}/Assets/ColorScheme/${colorScheme}/terminal/${terminal}/${colorScheme}-${mode}${extension}`
  }

  // ===== User Templates =====
  function buildUserTemplateCommand(input, mode) {
    if (!Settings.data.templates.enableUserTemplates) {
      return ""
    }

    const userConfigPath = getUserConfigPath()
    let script = "\n# Execute user config if it exists\n"
    script += `if [ -f '${userConfigPath}' ]; then\n`
    script += `  matugen image '${input}' --config '${userConfigPath}' --mode ${mode} --type ${Settings.data.colorSchemes.matugenSchemeType}\n`
    script += "fi"

    return script
  }

  function getUserConfigPath() {
    return (Quickshell.env("HOME") + "/.config/matugen/config.toml").replace(/'/g, "'\\''")
  }

  // ===== Utilities =====
  function selectVibrantColor(schemeData, mode) {
    const colors = [schemeData[mode]["mPrimary"], schemeData[mode]["mSecondary"], schemeData[mode]["mTertiary"]]

    let bestScore = 0
    let bestIndex = 0

    colors.forEach((color, i) => {
                     const hsl = ColorsConvert.hexToHSL(color)
                     if (hsl.s > bestScore) {
                       bestScore = hsl.s
                       bestIndex = i
                     }
                   })

    return colors[bestIndex]
  }

  // ===== Processes =====
  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("MatugenService", "GenerateProcess stderr:", this.text)
        }
      }
    }
  }

  Process {
    id: copyProcess
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("MatugenService", "CopyProcess stderr:", this.text)
        }
      }
    }
  }
}
