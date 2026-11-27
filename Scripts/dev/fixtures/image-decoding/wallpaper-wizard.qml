import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.SetupWizard
import qs.Services.Keyboard
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string url: Quickshell.env("IMAGE_REMOTE_URL")
  readonly property bool red: Quickshell.env("IMAGE_WIZARD_RED") === "1"
  readonly property bool extra: Quickshell.env("IMAGE_WIZARD_EXTRA") === "1"
  readonly property string monitor: Quickshell.screens[0].name
  property var wizard: null
  property string request: ""
  property string tail: ""
  property string detached: ""
  property int stage: 0
  property int ticks: 0
  property int pending: 0
  property bool copying: false
  property var snapshots: []
  property var saves: []
  property var terminals: []
  property var settlements: []
  property var reentrantSettlements: []
  property var legacy: []
  property var restored: null
  property var captured: null
  property var immediate: null
  property bool finished: false
  function makeWizard() {
    root.wizard = wizardFactory.createObject(root);
  }
  function retireAndProbe() {
    var ticket = WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "light", function () {
      root.legacy.push("cancelled");
    }, undefined, function (outcome) {
      root.settlements.push(outcome);
    });
    ticket.cancel();
    ticket.cancel();
    WallpaperService.changeWallpaper("", root.monitor, "light", null, undefined, function (outcome) {
      root.settlements.push(outcome);
    });
    WallpaperService.changeWallpaper(root.inputs + "/frame-0.png", root.monitor, "light", null, undefined, function (outcome) {
      root.reentrantSettlements.push({
                                       name: "first",
                                       outcome: outcome
                                     });
      var latest = WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", undefined, "light", null, undefined, function (result) {
        root.reentrantSettlements.push({
                                         name: "latest",
                                         outcome: result
                                       });
      });
      latest.cancel();
    });
    var other = WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", "other-monitor", "light", null, undefined, function (outcome) {
      root.reentrantSettlements.push({
                                       name: "other",
                                       outcome: outcome
                                     });
    });
    WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", undefined, "light", null, undefined, function (outcome) {
      root.reentrantSettlements.push({
                                       name: "superseding",
                                       outcome: outcome
                                     });
    });
    other.cancel();
    backdrop.requestedWallpaperPath = "";
  }
  function submit(path, scale) {
    wizard.selectedWallpaper = path;
    wizard.selectedWallpaperDirectory = root.inputs;
    wizard.selectedScaleRatio = scale;
    wizard.selectedBarPosition = "bottom";
    wizard.selectedBindingEnvironment = "none";
    wizard.completeSetup();
    root.request = wizard._submittedId;
  }
  function snapshot(name, after) {
    root.snapshots.push({
                          name: name,
                          path: WallpaperService.getWallpaper(root.monitor),
                          request: BindingsService.requestStatus(root.request),
                          state: BindingsService.state,
                          scale: Settings.data.general.scaleRatio,
                          bar: Settings.data.bar.position,
                          directory: Settings.data.wallpaper.directory,
                          image: backdrop.imageState
                        });
    if (backdrop.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
      if (after)
        after();
    })) {
      ++root.pending;
    } else {
      console.error("Wizard backdrop grab rejected: " + name);
      Qt.exit(3);
    }
  }
  Component {
    id: wizardFactory
    SetupWizard {
      screen: Quickshell.screens[0]
      property var modelData: Quickshell.screens[0]
    }
  }
  Process {
    id: repair
    command: ["cp", root.inputs + "/Still.webp", root.inputs + "/Retry.webp"]
    onExited: (code, status) => {
      root.copying = false;
      if (code !== 0)
        Qt.exit(4);
      root.wizard.retryRetainedHead();
      root.stage = 4;
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 192
    implicitHeight: 128
    color: "transparent"
    AtmoWallpaperBackground {
      id: backdrop
      screen: Quickshell.screens[0]
      fallbackColor: "#151515"
    }
    Image {
      id: raw
      visible: false
      source: root.inputs + "/Still.webp"
    }
  }
  Connections {
    target: Settings
    function onSettingsSaveCompleted(result) {
      root.saves.push({
                        stage: root.stage,
                        path: WallpaperService.getWallpaper(root.monitor),
                        result: result
                      });
    }
  }
  Connections {
    target: BindingsService
    function onRequestFinished(id, attempt, environment, success, error) {
      root.terminals.push({
                            id: id,
                            attempt: attempt,
                            success: success,
                            error: error,
                            path: WallpaperService.getWallpaper(root.monitor)
                          });
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    WallpaperService.init();
    Settings.data.general.animationDisabled = true;
    BindingsService.init(function (environment, done) {
      done(true, "");
    });
    root.makeWizard();
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      // The capture continuation owns the next request and stage until both
      // have been installed. Do not inspect the previous request meanwhile.
      if (!WallpaperService.isInitialized || root.finished || root.pending)
        return;
      ++root.ticks;
      var status = root.request ? BindingsService.requestStatus(root.request) : null;
      if (root.stage === 0) {
        WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", root.monitor);
        root.stage = 1;
      } else if (root.stage === 1 && root.extra && backdrop.imageState === "ready") {
        root.stage = 10;
        WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", "other-monitor", "light", function (success) {
          if (!success)
            Qt.exit(5);
          root.submit(root.url + "/partial.jpg", 1.55);
          WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor);
        });
      } else if (root.stage === 1 && backdrop.imageState === "ready") {
        root.stage = 2;
        root.submit(root.inputs + (root.red ? "/Corrupt.webp" : "/Motion.webp"), 1.15);
        root.immediate = {
          path: WallpaperService.getWallpaper(root.monitor),
          status: BindingsService.requestStatus(root.request),
          saves: root.saves.length
        };
        root.captured = BindingsService.requestStatus(root.request).work;
        root.wizard.selectedScaleRatio = 1.65;
        root.wizard.selectedWallpaper = root.inputs + "/frame-2.png";
      } else if (root.red && root.stage === 2 && status && status.status !== "Running") {
        root.finished = true;
        root.snapshot("red", function () {
          backdrop.requestedWallpaperPath = "";
          root.stage = 99;
          root.finished = false;
        });
      } else if (!root.red && root.stage === 2 && status.status === "Succeeded" && backdrop.imageState === "ready") {
        root.snapshot("valid", function () {
          root.submit(root.inputs + "/Retry.webp", 1.25);
          root.stage = 3;
        });
      } else if (root.stage === 3 && status.status === "Stopped" && !root.copying) {
        root.snapshots.push({
                              name: "failed",
                              request: status,
                              saves: root.saves.length,
                              scale: Settings.data.general.scaleRatio,
                              path: WallpaperService.getWallpaper(root.monitor)
                            });
        root.tail = BindingsService.requestEnvironment("none");
        root.wizard.selectedScaleRatio = 1.75;
        root.wizard.selectedWallpaper = root.inputs + "/frame-2.png";
        root.copying = true;
        repair.running = true;
      } else if (root.stage === 4 && status.status === "Succeeded" && BindingsService.requestStatus(root.tail).status === "Succeeded" && backdrop.imageState === "ready") {
        root.snapshot("retry", function () {
          root.submit(root.url + "/slow.jpg", 1.35);
          root.stage = 5;
        });
      } else if (root.stage === 5 && status.status === "Running" && Object.values(WallpaperService._wallpaperChanges).some(change => change.request && change.path.endsWith("/slow.jpg"))) {
        root.stage = 6;
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor);
      } else if (root.stage === 6 && status.status === "Stopped") {
        root.snapshots.push({
                              name: "superseded",
                              request: status,
                              scale: Settings.data.general.scaleRatio
                            });
        root.wizard.destroy();
        root.wizard = null;
        root.stage = 7;
      } else if (root.stage === 7) {
        root.makeWizard();
        root.restored = {
          id: root.wizard._submittedId,
          work: root.wizard._submittedWork,
          scale: root.wizard.selectedScaleRatio,
          wallpaper: root.wizard.selectedWallpaper
        };
        root.wizard.retryRetainedHead();
        root.stage = 8;
      } else if (root.stage === 8 && status.status === "Succeeded" && backdrop.imageState === "ready") {
        root.snapshot("reopened", function () {
          root.submit(root.url + "/detached.jpg", 1.45);
          root.detached = root.request;
          root.wizard.destroy();
          root.wizard = null;
          root.stage = 9;
        });
      } else if (root.stage === 9 && status.status === "Succeeded" && backdrop.imageState === "ready") {
        root.stage = 13;
        root.snapshot("detached", root.retireAndProbe);
      } else if (root.stage === 10 && status && status.status === "Stopped") {
        root.snapshots.push({
                              name: "partial",
                              request: status,
                              scale: Settings.data.general.scaleRatio,
                              other: WallpaperService.getWallpaper("other-monitor")
                            });
        root.wizard.retryRetainedHead();
        root.stage = 11;
      } else if (root.stage === 11 && status.status === "Succeeded" && backdrop.imageState === "ready") {
        root.snapshot("all-targets", function () {
          root.submit("", 1.65);
          root.stage = 12;
        });
      } else if (root.stage === 12 && status.status === "Succeeded") {
        root.stage = 13;
        root.snapshot("no-selection", root.retireAndProbe);
      } else if ((root.stage === 13 || root.stage === 99) && !root.pending && Object.keys(WallpaperService._wallpaperChanges).length === 0) {
        root.finished = true;
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         snapshots: root.snapshots,
                                                         saves: root.saves,
                                                         terminals: root.terminals,
                                                         immediate: root.immediate,
                                                         captured: root.captured,
                                                         restored: root.restored,
                                                         settlements: root.settlements,
                                                         reentrantSettlements: root.reentrantSettlements,
                                                         legacy: root.legacy,
                                                         detached: root.detached,
                                                         raw: raw.status,
                                                         changes: Object.keys(WallpaperService._wallpaperChanges).length,
                                                         reservations: Object.keys(WallpaperService._wallpaperReservations).length,
                                                         queue: BindingsService.queueCount,
                                                         state: BindingsService.state
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 23000
    running: true
    onTriggered: Qt.exit(3)
  }
}
