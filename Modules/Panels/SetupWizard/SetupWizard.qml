import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
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

    property int currentStep: 0
    readonly property int totalSteps: 5
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

        UpdateService.markChangelogSeen(UpdateService.currentVersion);

        Settings.saveImmediate();
        Logger.i("SetupWizard", "Setup completed successfully, waiting for settings save confirmation");

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

      // Step indicator navbar at top
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 32

        RowLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          Repeater {
            model: [
              {
                "icon": Icon.featured,
                "label": I18n.tr("setup.welcome")
              },
              {
                "icon": Icon.image,
                "label": I18n.tr("common.wallpaper")
              },
              {
                "icon": Icon.palette,
                "label": I18n.tr("common.appearance")
              },
              {
                "icon": Icon.settings,
                "label": I18n.tr("common.customize")
              },
              {
                "icon": Icon.deviceDesktop,
                "label": I18n.tr("panels.dock.title")
              }
            ]
            delegate: RowLayout {
              spacing: Style.marginS

              Rectangle {
                width: 24
                height: 24
                radius: width / 2
                color: index <= currentStep ? Color.mPrimary : Color.mSurfaceVariant
                border.color: index === currentStep ? Color.mPrimary : "transparent"
                border.width: index === currentStep ? 2 : 0

                NIcon {
                  anchors.centerIn: parent
                  icon: modelData.icon
                  pointSize: Style.fontSizeS
                  color: index <= currentStep ? Color.mOnPrimary : Color.mOnSurfaceVariant
                }
              }

              NText {
                text: modelData.label
                pointSize: Style.fontSizeS
                color: index <= currentStep ? Color.mPrimary : Color.mOnSurfaceVariant
                font.weight: index === currentStep ? Style.fontWeightBold : Style.fontWeightRegular
              }

              Rectangle {
                width: 40
                height: 2
                radius: 1
                color: index < currentStep ? Color.mPrimary : Color.mSurfaceVariant
                visible: index < totalSteps - 1
              }
            }
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
      }

      // Step content
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Math.round(300 * Style.uiScaleRatio)

        StackLayout {
          id: stepStack
          anchors.fill: parent
          currentIndex: currentStep

          SetupWelcomeStep {}

          SetupWallpaperStep {
            id: step1
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

          SetupAppearanceStep {
            id: step3
          }

          SetupCustomizeStep {
            id: step2
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

          SetupDockStep {
            id: stepDock
          }
        }
      }

      // Divider
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.2
      }

      // Bottom controls
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 44

        NButton {
          text: I18n.tr("setup.skip-setup")
          outlined: true
          Layout.preferredHeight: 44
          onClicked: panelContent.completeSetup()
        }

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: "← " + I18n.tr("common.back")
          outlined: true
          visible: currentStep > 0
          Layout.preferredHeight: 44
          onClicked: {
            if (currentStep > 0)
              currentStep--;
          }
        }

        NButton {
          text: currentStep === totalSteps - 1 ? I18n.tr("setup.all-done") : I18n.tr("common.continue") + " →"
          Layout.preferredHeight: 44
          onClicked: {
            if (currentStep < totalSteps - 1)
              currentStep++;
            else
              panelContent.completeSetup();
          }
        }
      }

      // Privacy notice — shown inside the Welcome step
    }
  }
}
