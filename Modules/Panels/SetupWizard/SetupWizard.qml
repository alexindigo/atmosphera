import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.MainScreen
import qs.Services
import qs.Services.Keyboard
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

  property string selectedBindingEnvironment: "none"
  property string selectedWallpaperDirectory: Settings.defaultWallpapersDirectory
  property string selectedWallpaper: ""
  property real selectedScaleRatio: 1.0
  property string selectedBarPosition: "top"
  property string _submittedId: ""
  property var _submittedWork: null
  property int _seenAttempt: 0
  readonly property string submissionContext: "setup-wizard:" + (root.screen ? root.screen.name : "default")
  readonly property var submittedStatus: BindingsService.requestStatus(root._submittedId)
  readonly property bool workOutstanding: root.submittedStatus && root.submittedStatus.status !== "Succeeded"

  function restoreSelection() {
    var existing = BindingsService.latestRequestForContext(root.submissionContext);
    var status = existing ? BindingsService.requestStatus(existing) : null;
    if (status && status.status !== "Succeeded") {
      root._submittedId = existing;
      root._submittedWork = status.work;
      root.selectedBindingEnvironment = status.environment;
      root.selectedWallpaperDirectory = status.work.wallpaperDirectory;
      root.selectedWallpaper = status.work.wallpaper;
      root.selectedScaleRatio = status.work.scaleRatio;
      root.selectedBarPosition = status.work.barPosition;
    } else {
      root._submittedId = "";
      root._submittedWork = null;
      root._seenAttempt = 0;
      root.selectedBindingEnvironment = Settings.data.bindings.environment || "none";
      root.selectedScaleRatio = Settings.data.general.scaleRatio;
      root.selectedBarPosition = Settings.data.bar.position;
      root.selectedWallpaperDirectory = Settings.data.wallpaper.directory || Settings.defaultWallpapersDirectory;
    }
  }

  function consumeResult(success, error, requestId, attemptId) {
    if (!root._submittedId && root._submittedWork)
      root._submittedId = requestId;
    if (requestId !== root._submittedId || attemptId <= root._seenAttempt)
      return;
    root._seenAttempt = attemptId;
    if (success) {
      Logger.i("SetupWizard", "Captured setup saved/deployed; niri handoff accepted where applicable");
      root.close();
    } else {
      Logger.e("SetupWizard", "Captured setup retained after stopped attempt", requestId, error);
    }
  }

  function prepareCapturedSetup(work, complete, requestId) {
    try {
      if (work.wallpaperDirectory !== Settings.data.wallpaper.directory) {
        Settings.data.wallpaper.directory = work.wallpaperDirectory;
        if (typeof WallpaperService !== "undefined") WallpaperService.refreshWallpapersList();
      }
      if (work.wallpaper !== "" && typeof WallpaperService !== "undefined")
        WallpaperService.changeWallpaper(work.wallpaper, undefined);
      Settings.saveSetupWork(work, function (success, error) {
        if (success) Version.markChangelogSeen(Version.currentVersion);
        complete(success, error);
      }, requestId);
    } catch (error) {
      complete(false, "Captured ordinary setup could not be saved");
    }
  }

  function retryRetainedHead() {
    if (BindingsService.state !== "Stopped")
      return;
    if (BindingsService.headRequestId === root._submittedId)
      BindingsService.retryHead(root.consumeResult);
    else
      BindingsService.retryHead(); // another caller's completion cannot close us
  }

  function completeSetup() {
    if (root.workOutstanding) {
      root.retryRetainedHead();
      return;
    }
    root._seenAttempt = 0;
    root._submittedWork = { "scaleRatio": root.selectedScaleRatio, "barPosition": root.selectedBarPosition,
      "wallpaperDirectory": root.selectedWallpaperDirectory, "wallpaper": root.selectedWallpaper };
    root._submittedId = BindingsService.requestEnvironment(root.selectedBindingEnvironment, root.consumeResult,
      { "context": root.submissionContext, "work": root._submittedWork, "prepare": root.prepareCapturedSetup });
  }

  function applyWallpaperSettings() {
    if (root.workOutstanding) return;
    if (root.selectedWallpaperDirectory !== Settings.data.wallpaper.directory) {
      Settings.data.wallpaper.directory = root.selectedWallpaperDirectory;
      if (typeof WallpaperService !== "undefined") WallpaperService.refreshWallpapersList();
    }
    if (root.selectedWallpaper !== "" && typeof WallpaperService !== "undefined")
      WallpaperService.changeWallpaper(root.selectedWallpaper, undefined);
  }

  function applyUISettings() {
    if (root.workOutstanding) return;
    Settings.data.general.scaleRatio = root.selectedScaleRatio;
    Settings.data.bar.position = root.selectedBarPosition;
  }

  Component.onCompleted: root.restoreSelection()
  onOpened: root.restoreSelection()
  Connections {
    target: BindingsService
    function onRequestFinished(requestId, attemptId, environment, success, error) {
      if (requestId === root._submittedId) root.consumeResult(success, error, requestId, attemptId);
    }
  }

  panelContent: Item {
    id: panelContent

    ColumnLayout {
      id: wizardContent
      anchors.fill: parent
      anchors.margins: Style.marginXL
      spacing: Style.marginL

      WizardPanel {
        id: wizard
        Layout.fillWidth: true
        Layout.fillHeight: true
        controlsLocked: root.workOutstanding
        retryAvailable: root.workOutstanding && BindingsService.state === "Stopped"

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
            "reset": function () { if (!root.workOutstanding) root.selectedBindingEnvironment = "none"; },
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

        onFinished: root.completeSetup()
        onSkipped: root.completeSetup()
      }
      NBindingsQueueStatus {
        Layout.fillWidth: true
        visible: root.workOutstanding
        queueStatus: BindingsService.status
        retry: root.retryRetainedHead
      }
    }

    Component {
      id: welcomeContent
      SetupWelcomeStep {}
    }

    Component {
      id: wallpaperContent
      SetupWallpaperStep {
        selectedDirectory: root.selectedWallpaperDirectory
        selectedWallpaper: root.selectedWallpaper
        onDirectoryChanged: function (d) {
          root.selectedWallpaperDirectory = d;
          root.applyWallpaperSettings();
        }
        onWallpaperChanged: function (w) {
          root.selectedWallpaper = w;
          root.applyWallpaperSettings();
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
        selectedScaleRatio: root.selectedScaleRatio
        selectedBarPosition: root.selectedBarPosition
        onScaleRatioChanged: function (r) {
          root.selectedScaleRatio = r;
          root.applyUISettings();
        }
        onBarPositionChanged: function (p) {
          root.selectedBarPosition = p;
          root.applyUISettings();
        }
      }
    }

    Component {
      id: bindingsContent
      SetupBindingsStep {
        selection: root.selectedBindingEnvironment
        selectionEnabled: !root.workOutstanding
        select: function (choice) { if (!root.workOutstanding) root.selectedBindingEnvironment = choice; }
      }
    }

    Component {
      id: dockContent
      SetupDockStep {}
    }
  }
}
