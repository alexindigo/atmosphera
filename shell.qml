
/*
 * Noctalia – made by https://github.com/noctalia-dev
 * Licensed under the MIT License.
 * Forks and modifications are allowed under the MIT License,
 * but proper credit must be given to the original author.
*/

// Qt & Quickshell Core
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Widgets

// Commons & Services
import qs.Commons
import qs.Services
import qs.Widgets

// Core Modules
import qs.Modules.Background
import qs.Modules.Dock
import qs.Modules.LockScreen
import qs.Modules.SessionMenu

// Bar & Bar Components
import qs.Modules.Bar
import qs.Modules.Bar.Extras
import qs.Modules.Bar.Audio
import qs.Modules.Bar.Bluetooth
import qs.Modules.Bar.Battery
import qs.Modules.Bar.Calendar
import qs.Modules.Bar.WiFi

// Panels & UI Components
import qs.Modules.ControlCenter
import qs.Modules.Launcher
import qs.Modules.Notification
import qs.Modules.OSD
import qs.Modules.Settings
import qs.Modules.Toast
import qs.Modules.Wallpaper
import qs.Modules.SetupWizard

ShellRoot {
  id: shellRoot

  property bool i18nLoaded: false
  property bool settingsLoaded: false

  Component.onCompleted: {
    Logger.i("Shell", "---------------------------")
    Logger.i("Shell", "Noctalia Hello!")
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() {
      Quickshell.inhibitReloadPopup()
    }
  }

  Connections {
    target: I18n ? I18n : null
    function onTranslationsLoaded() {
      i18nLoaded = true
    }
  }

  Connections {
    target: Settings ? Settings : null
    function onSettingsLoaded() {
      settingsLoaded = true
    }
  }

  // ------------------------------
  // Define panel components (must be at ShellRoot level for NFullScreenWindow access)
  Component {
    id: launcherComponent
    Launcher {}
  }

  Component {
    id: controlCenterComponent
    ControlCenterPanel {}
  }

  Component {
    id: calendarComponent
    CalendarPanel {}
  }

  Component {
    id: settingsComponent
    SettingsPanel {}
  }

  Component {
    id: directWidgetSettingsComponent
    DirectWidgetSettingsPanel {}
  }

  Component {
    id: notificationHistoryComponent
    NotificationHistoryPanel {}
  }

  Component {
    id: sessionMenuComponent
    SessionMenu {}
  }

  Component {
    id: wifiComponent
    WiFiPanel {}
  }

  Component {
    id: bluetoothComponent
    BluetoothPanel {}
  }

  Component {
    id: audioComponent
    AudioPanel {}
  }

  Component {
    id: wallpaperComponent
    WallpaperPanel {}
  }

  Component {
    id: batteryComponent
    BatteryPanel {}
  }

  Component {
    id: barComp
    Bar {}
  }

  Loader {
    active: i18nLoaded && settingsLoaded

    sourceComponent: Item {
      Component.onCompleted: {
        Logger.i("Shell", "---------------------------")
        WallpaperService.init()
        AppThemeService.init()
        ColorSchemeService.init()
        BarWidgetRegistry.init()
        LocationService.init()
        NightLightService.apply()
        DarkModeService.init()
        FontService.init()
        HooksService.init()
        BluetoothService.init()
        BatteryService.init()
        IdleInhibitorService.init()
        PowerProfileService.init()
        DistroService.init()
      }

      Background {}
      Overview {}

      Dock {}

      Notification {
        id: notification
      }

      LockScreen {
        id: lockScreen
        Component.onCompleted: {
          // Save a ref. to our lockScreen so we can access it  easily
          PanelService.lockScreen = lockScreen
        }
      }

      ToastOverlay {}
      OSD {}

      // IPCService is treated as a service
      // but it's actually an Item that needs to exists in the shell.
      IPCService {}
    }
  }

  // ------------------------------
  // NFullScreenWindow for each screen (manages bar + all panels)
  // Wrapped in Loader to optimize memory - only loads when screen needs it
  Variants {
    model: Quickshell.screens
    delegate: Item {
      required property ShellScreen modelData

      property bool shouldBeActive: {
        if (!i18nLoaded || !settingsLoaded)
          return false
        if (!BarService.isVisible)
          return false
        if (!modelData || !modelData.name)
          return false

        var monitors = Settings.data.bar.monitors || []
        var result = monitors.length === 0 || monitors.includes(modelData.name)

        Logger.d("Shell", "NFullScreenWindow Loader for", modelData?.name, "- shouldBeActive:", result, "- monitors:", JSON.stringify(monitors))
        return result
      }

      property bool windowLoaded: false

      Loader {
        id: windowLoader
        active: parent.shouldBeActive
        asynchronous: false

        property ShellScreen loaderScreen: modelData

        onLoaded: {
          // Signal that window is loaded so exclusion zone can be created
          parent.windowLoaded = true
        }

        sourceComponent: NFullScreenWindow {
          screen: windowLoader.loaderScreen

          // Register all panel components
          panelComponents: [{
              "id": "launcherPanel",
              "component": launcherComponent,
              "zIndex": 50
            }, {
              "id": "controlCenterPanel",
              "component": controlCenterComponent,
              "zIndex": 50
            }, {
              "id": "calendarPanel",
              "component": calendarComponent,
              "zIndex": 50
            }, {
              "id": "settingsPanel",
              "component": settingsComponent,
              "zIndex": 50
            }, {
              "id": "directWidgetSettingsPanel",
              "component": directWidgetSettingsComponent,
              "zIndex": 50
            }, {
              "id": "notificationHistoryPanel",
              "component": notificationHistoryComponent,
              "zIndex": 50
            }, {
              "id": "sessionMenuPanel",
              "component": sessionMenuComponent,
              "zIndex": 50
            }, {
              "id": "wifiPanel",
              "component": wifiComponent,
              "zIndex": 50
            }, {
              "id": "bluetoothPanel",
              "component": bluetoothComponent,
              "zIndex": 50
            }, {
              "id": "audioPanel",
              "component": audioComponent,
              "zIndex": 50
            }, {
              "id": "wallpaperPanel",
              "component": wallpaperComponent,
              "zIndex": 50
            }, {
              "id": "batteryPanel",
              "component": batteryComponent,
              "zIndex": 50
            }]

          // Bar component
          barComponent: barComp
        }
      }

      // BarExclusionZone - created after NFullScreenWindow has fully loaded
      // Must also be disabled when bar is disabled (follows shouldBeActive)
      Loader {
        active: parent.windowLoaded && parent.shouldBeActive
        asynchronous: false

        sourceComponent: BarExclusionZone {
          screen: modelData
        }

        onLoaded: {
          Logger.d("Shell", "BarExclusionZone created for", modelData?.name)
        }
      }
    }
  }

  // ------------------------------
  // Setup Wizard
  Loader {
    id: setupWizardLoader
    active: false
    asynchronous: true
    sourceComponent: SetupWizard {}
    onLoaded: {
      if (setupWizardLoader.item && setupWizardLoader.item.open) {
        setupWizardLoader.item.open()
      }
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      // Only open the setup wizard for new users
      if (!Settings.data.setupCompleted) {
        checkSetupWizard()
      }
    }
  }

  function checkSetupWizard() {
    // Wait for distro service
    if (!DistroService.isReady) {
      Qt.callLater(checkSetupWizard)
      return
    }

    // No setup wizard on NixOS
    if (DistroService.isNixOS) {
      Settings.data.setupCompleted = true
      return
    }

    if (Settings.data.settingsVersion >= Settings.settingsVersion) {
      setupWizardLoader.active = true
    } else {
      Settings.data.setupCompleted = true
    }
  }
}
