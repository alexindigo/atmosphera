
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

// Panel Windows
import qs.Modules.Background
import qs.Modules.Dock
import qs.Modules.MainScreen
import qs.Modules.LockScreen
import qs.Modules.Notification
import qs.Modules.OSD
import qs.Modules.Toast

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

      Overview {}
      Background {}
      Dock {}
      ToastOverlay {}
      OSD {}
      Notification {}

      LockScreen {
        id: lockScreen
        Component.onCompleted: {
          // Save a ref. to our lockScreen so we can access it  easily
          PanelService.lockScreen = lockScreen
        }
      }

      // IPCService is treated as a service but it's actually an
      // Item that needs to exists in the shell.
      IPCService {}

      // ------------------------------
      // MainScreen for each screen (manages bar + all panels)
      // Wrapped in Loader to optimize memory - only loads when screen needs it
      Variants {
        model: Quickshell.screens
        delegate: Item {
          required property ShellScreen modelData

          property bool shouldBeActive: {
            if (!modelData || !modelData.name)
              Logger.d("Shell", "MainScreen activated for", modelData?.name)
            return true
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

            sourceComponent: MainScreen {
              screen: windowLoader.loaderScreen
            }
          }

          // BarExclusionZone - created after MainScreen has fully loaded
          // Disabled when bar is hidden or not configured for this screen
          Loader {
            active: {
              if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
                return false

              // Check if bar is configured for this screen
              var monitors = Settings.data.bar.monitors || []
              return monitors.length === 0 || monitors.includes(modelData?.name)
            }
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
    }
  }

  // Setup Wizard - Auto Kick start
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
      // Open Setup Wizard as a panel in the same windowing system as Settings/ControlCenter
      if (Quickshell.screens.length > 0) {
        var targetScreen = Quickshell.screens[0]
        var setupPanel = PanelService.getPanel("setupWizardPanel", targetScreen)
        if (setupPanel) {
          setupPanel.open()
        } else {
          // If not yet loaded, ensure it loads and try again shortly
          Qt.callLater(() => {
                         var sp = PanelService.getPanel("setupWizardPanel", targetScreen)
                         if (sp)
                         sp.open()
                       })
        }
      }
    } else {
      Settings.data.setupCompleted = true
    }
  }
}
