pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

Singleton {
  id: root

  // Define our app directories
  // Default config directory: ~/.config/noctalia
  // Default cache directory: ~/.cache/noctalia
  property string shellName: "noctalia"
  property string configDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME")
                                                                       || Quickshell.env(
                                                                         "HOME") + "/.config") + "/" + shellName + "/"
  property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env(
                                                                       "HOME") + "/.cache") + "/" + shellName + "/"
  property string cacheDirImages: cacheDir + "images/"

  property string settingsFile: Quickshell.env("NOCTALIA_SETTINGS_FILE") || (configDir + "settings.json")

  property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"
  property string defaultVideosDirectory: Quickshell.env("HOME") + "/Videos"
  property string defaultLocation: "Tokyo"

  // Used to access via Settings.data.xxx.yyy
  readonly property alias data: adapter

  property bool isLoaded: false

  // Signal emitted when settings are loaded after startupcale changes
  signal settingsLoaded

  // -----------------------------------------------------
  // Function to validate monitor configurations
  function validateMonitorConfigurations() {
    var availableScreenNames = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      availableScreenNames.push(Quickshell.screens[i].name)
    }

    Logger.log("Settings", "Available monitors: [" + availableScreenNames.join(", ") + "]")
    Logger.log("Settings", "Configured bar monitors: [" + adapter.bar.monitors.join(", ") + "]")

    // Check bar monitors
    if (adapter.bar.monitors.length > 0) {
      var hasValidBarMonitor = false
      for (var j = 0; j < adapter.bar.monitors.length; j++) {
        if (availableScreenNames.includes(adapter.bar.monitors[j])) {
          hasValidBarMonitor = true
          break
        }
      }
      if (!hasValidBarMonitor) {
        Logger.warn("Settings",
                    "No configured bar monitors found on system, clearing bar monitor list to show on all screens")
        adapter.bar.monitors = []
      } else {

        //Logger.log("Settings", "Found valid bar monitors, keeping configuration")
      }
    } else {

      //Logger.log("Settings", "Bar monitor list is empty, will show on all available screens")
    }
  }

  // -----------------------------------------------------
  // If the settings structure has changed, ensure
  // backward compatibility
  function upgradeSettingsData() {
    for (var i = 0; i < adapter.bar.widgets.left.length; i++) {
      var obj = adapter.bar.widgets.left[i]
      if (typeof obj === "string") {
        adapter.bar.widgets.left[i] = {
          "id": obj
        }
      }
    }
    for (var i = 0; i < adapter.bar.widgets.center.length; i++) {
      var obj = adapter.bar.widgets.center[i]
      if (typeof obj === "string") {
        adapter.bar.widgets.center[i] = {
          "id": obj
        }
      }
    }
    for (var i = 0; i < adapter.bar.widgets.right.length; i++) {
      var obj = adapter.bar.widgets.right[i]
      if (typeof obj === "string") {
        adapter.bar.widgets.right[i] = {
          "id": obj
        }
      }
    }
  }

  // -----------------------------------------------------
  // Kickoff essential services
  function kickOffServices() {
    // Ensure our location singleton is created as soon as possible so we start fetching weather asap
    LocationService.init()

    NightLightService.apply()

    ColorSchemeService.init()

    MatugenService.init()

    FontService.init()

    HooksService.init()
  }

  // -----------------------------------------------------
  Item {
    Component.onCompleted: {

      // ensure settings dir exists
      Quickshell.execDetached(["mkdir", "-p", configDir])
      Quickshell.execDetached(["mkdir", "-p", cacheDir])
      Quickshell.execDetached(["mkdir", "-p", cacheDirImages])
    }
  }

  // Don't write settings to disk immediately
  // This avoid excessive IO when a variable changes rapidly (ex: sliders)
  Timer {
    id: saveTimer
    running: false
    interval: 1000
    onTriggered: settingsFileView.writeAdapter()
  }

  FileView {
    id: settingsFileView
    path: settingsFile
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: saveTimer.start()
    Component.onCompleted: function () {
      reload()
    }
    onLoaded: function () {
      if (!isLoaded) {
        Logger.log("Settings", "----------------------------")
        Logger.log("Settings", "Settings loaded successfully")
        isLoaded = true

        upgradeSettingsData()

        validateMonitorConfigurations()

        kickOffServices()

        // Emit the signal
        root.settingsLoaded()
      }
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2)
        // File doesn't exist, create it with default values
        writeAdapter()
    }

    JsonAdapter {
      id: adapter

      property int settingsVersion: 1

      // bar
      property JsonObject bar: JsonObject {
        property string position: "top" // Possible values: "top", "bottom"
        property bool showActiveWindowIcon: true
        property bool alwaysShowBatteryPercentage: false
        property bool showNetworkStats: false
        property real backgroundOpacity: 1.0
        property bool useDistroLogo: false
        property string showWorkspaceLabel: "none"
        property list<string> monitors: []

        // Widget configuration for modular bar system
        property JsonObject widgets
        widgets: JsonObject {
          property list<var> left: [{
              "id": "SystemMonitor"
            }, {
              "id": "ActiveWindow"
            }, {
              "id": "MediaMini"
            }]
          property list<var> center: [{
              "id": "Workspace"
            }]
          property list<var> right: [{
              "id": "ScreenRecorderIndicator"
            }, {
              "id": "Tray"
            }, {
              "id": "NotificationHistory"
            }, {
              "id": "WiFi"
            }, {
              "id": "Bluetooth"
            }, {
              "id": "Battery"
            }, {
              "id": "Volume"
            }, {
              "id": "Brightness"
            }, {
              "id": "NightLight"
            }, {
              "id": "Clock"
            }, {
              "id": "SidePanelToggle"
            }]
        }
      }

      // general
      property JsonObject general: JsonObject {
        property string avatarImage: defaultAvatar
        property bool dimDesktop: false
        property bool showScreenCorners: false
        property real radiusRatio: 1.0
        // Animation speed multiplier (0.1x - 2.0x)
        property real animationSpeed: 1.0
      }

      // location
      property JsonObject location: JsonObject {
        property string name: defaultLocation
        property bool useFahrenheit: false
        property bool reverseDayMonth: false
        property bool use12HourClock: false
        property bool showDateWithClock: false
      }

      // screen recorder
      property JsonObject screenRecorder: JsonObject {
        property string directory: defaultVideosDirectory
        property int frameRate: 60
        property string audioCodec: "opus"
        property string videoCodec: "h264"
        property string quality: "very_high"
        property string colorRange: "limited"
        property bool showCursor: true
        property string audioSource: "default_output"
        property string videoSource: "portal"
      }

      // wallpaper
      property JsonObject wallpaper: JsonObject {
        property bool enabled: true
        property string directory: defaultWallpapersDirectory
        property bool enableMultiMonitorDirectories: false
        property bool setWallpaperOnAllMonitors: true
        property string fillMode: "crop"
        property color fillColor: "#000000"
        property bool randomEnabled: false
        property int randomIntervalSec: 300 // 5 min
        property int transitionDuration: 1500 // 1500 ms
        property string transitionType: "random"
        property real transitionEdgeSmoothness: 0.05
        property list<var> monitors: []
      }

      // applauncher
      property JsonObject appLauncher: JsonObject {
        // When disabled, Launcher hides clipboard command and ignores cliphist
        property bool enableClipboardHistory: false
        // Position: center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
        property string position: "center"
        property real backgroundOpacity: 1.0
        property list<string> pinnedExecs: []
      }

      // dock
      property JsonObject dock: JsonObject {
        property bool autoHide: false
        property bool exclusive: false
        property list<string> monitors: []
      }

      // network
      property JsonObject network: JsonObject {
        property bool wifiEnabled: true
        property bool bluetoothEnabled: true
      }

      // notifications
      property JsonObject notifications: JsonObject {
        property list<string> monitors: []
      }

      // audio
      property JsonObject audio: JsonObject {
        property bool showMiniplayerAlbumArt: false
        property bool showMiniplayerCava: false
        property string visualizerType: "linear"
        property int volumeStep: 5
        property int cavaFrameRate: 60
        // MPRIS controls
        property list<string> mprisBlacklist: []
        property string preferredPlayer: ""
      }

      // ui
      property JsonObject ui: JsonObject {
        property string fontDefault: "Roboto" // Default font for all text
        property string fontFixed: "DejaVu Sans Mono" // Fixed width font for terminal
        property string fontBillboard: "Inter" // Large bold font for clocks and prominent displays
        property list<var> monitorsScaling: []
        property bool idleInhibitorEnabled: false
      }

      // brightness
      property JsonObject brightness: JsonObject {
        property int brightnessStep: 5
      }

      property JsonObject colorSchemes: JsonObject {
        property bool useWallpaperColors: false
        property string predefinedScheme: ""
        property bool darkMode: true
      }

      // matugen templates toggles
      property JsonObject matugen: JsonObject {
        // Per-template flags to control dynamic config generation
        property bool gtk4: false
        property bool gtk3: false
        property bool qt6: false
        property bool qt5: false
        property bool kitty: false
        property bool ghostty: false
        property bool foot: false
        property bool fuzzel: false
        property bool vesktop: false
        property bool enableUserTemplates: false
      }

      // night light
      property JsonObject nightLight: JsonObject {
        property bool enabled: false
        property bool autoSchedule: true
        property string nightTemp: "4000"
        property string dayTemp: "6500"
        property string manualSunrise: "06:30"
        property string manualSunset: "18:30"
      }

      // hooks
      property JsonObject hooks: JsonObject {
        property bool enabled: false
        property string wallpaperChange: ""
        property string darkModeChange: ""
      }
    }
  }
}
