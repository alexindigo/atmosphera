import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services
import qs.Services.System
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(preferredWidthRatio * 2560 * Style.uiScaleRatio)
  preferredHeight: Math.round(preferredHeightRatio * 1440 * Style.uiScaleRatio)
  preferredWidthRatio: 0.4
  preferredHeightRatio: 0.6

  panelAnchorHorizontalCenter: true
  panelAnchorVerticalCenter: true

  closeWithEscape: false

  panelContent: Item {
    id: panelContent

    property bool isCompleting: false

    property string selectedWallpaperDirectory: Settings.defaultWallpapersDirectory
    property string selectedWallpaper: ""
    property real selectedScaleRatio: 1.0
    property string selectedBarPosition: "top"

    Component.onCompleted: {
      selectedScaleRatio = Settings.data.general.scaleRatio;
      selectedBarPosition = Settings.data.bar.position;
      selectedWallpaperDirectory = Settings.data.wallpaper.directory || Settings.defaultWallpapersDirectory;
    }

    Connections {
      target: Settings
      function onSettingsSaved() {
        if (panelContent.isCompleting) {
          Logger.i("SetupWizard", "Settings saved, closing panel");
          panelContent.isCompleting = false;
          root.close();
        }
      }
    }

    Timer {
      id: closeTimer
      interval: 2000
      onTriggered: {
        if (panelContent.isCompleting) {
          Logger.w("SetupWizard", "Settings save timeout, closing panel anyway");
          panelContent.isCompleting = false;
          root.close();
        }
      }
    }

    function completeSetup() {
      if (isCompleting) {
        Logger.w("SetupWizard", "completeSetup() called while already completing, ignoring");
        return;
      }

      try {
        Logger.i("SetupWizard", "Completing setup with selected options");
        isCompleting = true;

        if (typeof WallpaperService !== "undefined" && WallpaperService.refreshWallpapersList) {
          if (selectedWallpaperDirectory !== Settings.data.wallpaper.directory) {
            Settings.data.wallpaper.directory = selectedWallpaperDirectory;
            WallpaperService.refreshWallpapersList();
          }

          if (selectedWallpaper !== "") {
            WallpaperService.changeWallpaper(selectedWallpaper, undefined);
          }
        }

        Settings.data.general.scaleRatio = selectedScaleRatio;
        Settings.data.bar.position = selectedBarPosition;

        Version.markChangelogSeen(Version.currentVersion);

        Settings.saveImmediate();
        Logger.i("SetupWizard", "Setup completed successfully, waiting for settings save confirmation");

        // Deploy bindings if the user picked a non-"none" environment.
        if (Settings.data.bindings.environment && Settings.data.bindings.environment !== "none") {
          Quickshell.execDetached(["atmosphera", "bindings", "apply"]);
          Logger.i("SetupWizard", "Triggered atmosphera bindings apply for env:", Settings.data.bindings.environment);
        }

        closeTimer.start();
      } catch (error) {
        Logger.e("SetupWizard", "Error completing setup:", error);
        isCompleting = false;
      }
    }

    function applyWallpaperSettings() {
      if (typeof WallpaperService !== "undefined" && WallpaperService.refreshWallpapersList) {
        if (selectedWallpaperDirectory !== Settings.data.wallpaper.directory) {
          Settings.data.wallpaper.directory = selectedWallpaperDirectory;
          WallpaperService.refreshWallpapersList();
        }

        if (selectedWallpaper !== "") {
          WallpaperService.changeWallpaper(selectedWallpaper, undefined);
        }
      }
    }

    function applyUISettings() {
      Settings.data.general.scaleRatio = selectedScaleRatio;
      Settings.data.bar.position = selectedBarPosition;
    }

    ColumnLayout {
      id: wizardContent
      anchors.fill: parent
      anchors.margins: Style.marginXL
      spacing: Style.marginL

      WizardPanel {
        id: wizard
        Layout.fillWidth: true
        Layout.fillHeight: true

        steps: [
          {
            "icon": "featured",
            "label": "",
            "content": welcomeContent
          },
          {
            "icon": "image",
            "label": I18n.tr("setup.wallpaper.header"),
            "description": I18n.tr("setup.wallpaper.subheader"),
            "resetKey": "wallpaper",
            "content": wallpaperContent
          },
          {
            "icon": "palette",
            "label": I18n.tr("common.appearance"),
            "description": I18n.tr("setup.appearance.subheader"),
            "resetKey": "colorSchemes",
            "content": appearanceContent
          },
          {
            "icon": "settings",
            "label": I18n.tr("setup.customize.header"),
            "description": I18n.tr("setup.customize.subheader"),
            "content": customizeContent
          },
          {
            "icon": "keyboard",
            "label": I18n.tr("setup.bindings.title"),
            "description": I18n.tr("setup.bindings.subtitle"),
            "resetKey": "bindings",
            "content": bindingsContent
          },
          {
            "icon": "device-desktop",
            "label": I18n.tr("panels.dock.title"),
            "description": I18n.tr("panels.dock.monitors-desc"),
            "resetKey": "dock",
            "content": dockContent
          }
        ]

        onFinished: panelContent.completeSetup()
        onSkipped: panelContent.completeSetup()
      }
    }

    Component {
      id: welcomeContent
      SetupWelcomeStep {}
    }

    Component {
      id: wallpaperContent
      SetupWallpaperStep {
        selectedDirectory: panelContent.selectedWallpaperDirectory
        selectedWallpaper: panelContent.selectedWallpaper
        onDirectoryChanged: function (d) {
          panelContent.selectedWallpaperDirectory = d;
          panelContent.applyWallpaperSettings();
        }
        onWallpaperChanged: function (w) {
          panelContent.selectedWallpaper = w;
          panelContent.applyWallpaperSettings();
        }
      }
    }

    Component {
      id: appearanceContent
      SetupAppearanceStep {}
    }

    Component {
      id: customizeContent
      SetupCustomizeStep {
        selectedScaleRatio: panelContent.selectedScaleRatio
        selectedBarPosition: panelContent.selectedBarPosition
        onScaleRatioChanged: function (r) {
          panelContent.selectedScaleRatio = r;
          panelContent.applyUISettings();
        }
        onBarPositionChanged: function (p) {
          panelContent.selectedBarPosition = p;
          panelContent.applyUISettings();
        }
      }
    }

    Component {
      id: bindingsContent
      SetupBindingsStep {}
    }

    Component {
      id: dockContent
      SetupDockStep {}
    }
  }
}
