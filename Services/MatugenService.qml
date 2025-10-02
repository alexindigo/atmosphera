pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Assets.Matugen
import qs.Services
import "../Helpers/ColorVariants.js" as ColorVariants

Singleton {
  id: root

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

  // Convert predefined color scheme to Matugen format
  function convertPredefinedSchemeToMatugen(schemeData) {
    var variant = schemeData
    // If scheme provides dark/light variants, pick based on settings
    if (schemeData && (schemeData.dark || schemeData.light)) {
      if (Settings.data.colorSchemes.darkMode) {
        variant = schemeData.dark || schemeData.light
      } else {
        variant = schemeData.light || schemeData.dark
      }
    }

    // Map predefined scheme colors to Matugen color structure - only core Material 3 colors
    var matugenColors = {
      "colors": {
        "primary": {
          "light": {
            "color": variant.mPrimary
          },
          "default": {
            "color": variant.mPrimary
          },
          "dark": {
            "color": variant.mPrimary
          }
        },
        "on_primary": {
          "light": {
            "color": variant.mOnPrimary
          },
          "default": {
            "color": variant.mOnPrimary
          },
          "dark": {
            "color": variant.mOnPrimary
          }
        },
        "secondary": {
          "light": {
            "color": variant.mSecondary
          },
          "default": {
            "color": variant.mSecondary
          },
          "dark": {
            "color": variant.mSecondary
          }
        },
        "on_secondary": {
          "light": {
            "color": variant.mOnSecondary
          },
          "default": {
            "color": variant.mOnSecondary
          },
          "dark": {
            "color": variant.mOnSecondary
          }
        },
        "tertiary": {
          "light": {
            "color": variant.mTertiary
          },
          "default": {
            "color": variant.mTertiary
          },
          "dark": {
            "color": variant.mTertiary
          }
        },
        "on_tertiary": {
          "light": {
            "color": variant.mOnTertiary
          },
          "default": {
            "color": variant.mOnTertiary
          },
          "dark": {
            "color": variant.mOnTertiary
          }
        },
        "error": {
          "light": {
            "color": variant.mError
          },
          "default": {
            "color": variant.mError
          },
          "dark": {
            "color": variant.mError
          }
        },
        "on_error": {
          "light": {
            "color": variant.mOnError
          },
          "default": {
            "color": variant.mOnError
          },
          "dark": {
            "color": variant.mOnError
          }
        },
        "surface": {
          "light": {
            "color": variant.mSurface
          },
          "default": {
            "color": variant.mSurface
          },
          "dark": {
            "color": variant.mSurface
          }
        },
        "on_surface": {
          "light": {
            "color": variant.mOnSurface
          },
          "default": {
            "color": variant.mOnSurface
          },
          "dark": {
            "color": variant.mOnSurface
          }
        },
        "surface_variant": {
          "light": {
            "color": variant.mSurfaceVariant
          },
          "default": {
            "color": variant.mSurfaceVariant
          },
          "dark": {
            "color": variant.mSurfaceVariant
          }
        },
        "on_surface_variant": {
          "light": {
            "color": variant.mOnSurfaceVariant
          },
          "default": {
            "color": variant.mOnSurfaceVariant
          },
          "dark": {
            "color": variant.mOnSurfaceVariant
          }
        },
        "outline": {
          "light": {
            "color": variant.mOutline
          },
          "default": {
            "color": variant.mOutline
          },
          "dark": {
            "color": variant.mOutline
          }
        },
        "primary_fixed_dim": {
          "light": {
            "color": ColorVariants.generateFixedDim(variant.mPrimary)
          },
          "default": {
            "color": ColorVariants.generateFixedDim(variant.mPrimary)
          },
          "dark": {
            "color": ColorVariants.generateFixedDim(variant.mPrimary)
          }
        },
        "secondary_fixed_dim": {
          "light": {
            "color": ColorVariants.generateFixedDim(variant.mSecondary)
          },
          "default": {
            "color": ColorVariants.generateFixedDim(variant.mSecondary)
          },
          "dark": {
            "color": ColorVariants.generateFixedDim(variant.mSecondary)
          }
        },
        "tertiary_fixed_dim": {
          "light": {
            "color": ColorVariants.generateFixedDim(variant.mTertiary)
          },
          "default": {
            "color": ColorVariants.generateFixedDim(variant.mTertiary)
          },
          "dark": {
            "color": ColorVariants.generateFixedDim(variant.mTertiary)
          }
        },
        "surface_bright": {
          "light": {
            "color": ColorVariants.generateBright(variant.mSurface)
          },
          "default": {
            "color": ColorVariants.generateBright(variant.mSurface)
          },
          "dark": {
            "color": ColorVariants.generateBright(variant.mSurface)
          }
        },
        "surface_variant_bright": {
          "light": {
            "color": ColorVariants.generateBright(variant.mSurfaceVariant)
          },
          "default": {
            "color": ColorVariants.generateBright(variant.mSurfaceVariant)
          },
          "dark": {
            "color": ColorVariants.generateBright(variant.mSurfaceVariant)
          }
        }
      }
    }

    return JSON.stringify(matugenColors)
  }

  // Generate colors using current wallpaper and settings
  function generateFromWallpaper() {
    Logger.log("Matugen", "Generating from wallpaper on screen:", Screen.name)
    var wp = WallpaperService.getWallpaper(Screen.name).replace(/'/g, "'\\''")
    if (wp === "") {
      Logger.error("Matugen", "No wallpaper was found")
      return
    }

    var content = Matugen.buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")

    // Build the main script
    var script = "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n" + "for d in '" + extraRepo + "' '" + extraUser + "'; do\n" + "  if [ -d \"$d\" ]; then\n" + "    for f in \"$d\"/*.toml; do\n" + "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '" + pathEsc + "'\n" + "    done\n" + "  fi\n"
        + "done\n" + "matugen image '" + wp + "' --config '" + pathEsc + "' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType

    // Add user config execution if enabled
    if (Settings.data.matugen.enableUserTemplates) {
      var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
      script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
      script += "  matugen image '" + wp + "' --config '" + userConfigDir + "config.toml' --mode " + mode + " --type " + Settings.data.colorSchemes.matugenSchemeType + "\n"
      script += "fi"
    }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]
    generateProcess.running = true
  }

  // Generate templates from predefined color scheme
  function generateFromPredefinedScheme(schemeData) {
    Logger.log("Matugen", "Generating templates from predefined color scheme")

    var content = Matugen.buildConfigToml()
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light"
    var pathEsc = dynamicConfigPath.replace(/'/g, "'\\''")
    var extraRepo = (Quickshell.shellDir + "/Assets/Matugen/extra").replace(/'/g, "'\\''")
    var extraUser = (Settings.configDir + "matugen.d").replace(/'/g, "'\\''")

    // Convert predefined scheme to Matugen format
    var matugenJson = convertPredefinedSchemeToMatugen(schemeData)
    var jsonPath = Settings.cacheDir + "matugen.import.json"
    var jsonPathEsc = jsonPath.replace(/'/g, "'\\''")

    // Build the script
    var script = ""
    script += "cat > '" + pathEsc + "' << 'EOF'\n" + content + "EOF\n"
    script += "for d in '" + extraRepo + "' '" + extraUser + "'; do\n"
    script += "  if [ -d \"$d\" ]; then\n"
    script += "    for f in \"$d\"/*.toml; do\n"
    script += "      [ -f \"$f\" ] && { echo; echo \"# extra: $f\"; cat \"$f\"; } >> '" + pathEsc + "'\n"
    script += "    done\n"
    script += "  fi\n"
    script += "done\n"
    script += "matugen image --import-json '" + jsonPathEsc + "' --config '" + pathEsc + "' --mode " + mode + " '" + Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png'"

    // Add user config execution if enabled
    if (Settings.data.matugen.enableUserTemplates) {
      var userConfigDir = (Quickshell.env("HOME") + "/.config/matugen/").replace(/'/g, "'\\''")
      script += "\n# Execute user config if it exists\nif [ -f '" + userConfigDir + "config.toml' ]; then\n"
      script += "  matugen image --import-json '" + jsonPathEsc + "' --config '" + userConfigDir + "config.toml' --mode " + mode + " '" + Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png'\n"
      script += "fi"
    }

    script += "\n"
    generateProcess.command = ["bash", "-lc", script]

    // Write JSON file with our custom colors
    // once written matugen will be executed via 'generateProcess'
    jsonWriter.path = jsonPath
    jsonWriter.setText(matugenJson)
  }

  // File writer for JSON import file
  FileView {
    id: jsonWriter
    onSaved: {
      Logger.log("Matugen", "JSON import file written successfully")
      // Run matugen command after JSON file is written
      generateProcess.running = true
    }
    onSaveFailed: {
      Logger.error("Matugen", "Failed to write JSON import file:", error)
    }
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
}
