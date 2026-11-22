import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string monitor: Quickshell.screens[0].name
  property var events: []
  property var snapshots: []
  property var callbacks: []
  property var notices: []
  property int tick: 0
  property int pending: 0
  property var cancelled: null
  property bool started: false
  property bool solidRequested: false
  property bool solidReasserted: false
  property string beforeFavorites: ""
  property string beforeTheme: ""
  property string immediatePath: ""

  function snapshot(name) {
    snapshots.push({
                     name: name,
                     path: WallpaperService.getWallpaperPathForSlot(monitor, "light"),
                     dark: WallpaperService.getWallpaperPathForSlot(monitor, "dark"),
                     other: WallpaperService.getWallpaperPathForSlot("other-monitor", "light"),
                     favorites: JSON.stringify(Settings.data.wallpaper.favorites),
                     theme: JSON.stringify([Settings.data.colorSchemes.predefinedScheme, Settings.data.colorSchemes.darkMode, Settings.data.colorSchemes.useWallpaperColors, Settings.data.colorSchemes.generationMethod]),
                     solid: Settings.data.wallpaper.useSolidColor,
                     resolved: backdrop.resolvedWallpaperPath,
                     state: backdrop.imageState
                   });
    ++pending;
    backdrop.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    });
  }
  FloatingWindow {
    visible: true
    implicitWidth: 192
    implicitHeight: 128
    color: "transparent"
    AtmoWallpaperBackground {
      id: backdrop
      screen: Quickshell.screens[0]
    }
  }
  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      root.events.push({
                         screen: screenName,
                         path: path,
                         tick: root.tick
                       });
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices.push({
                          tick: root.tick,
                          title: title,
                          reason: description,
                          type: type
                        });
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    WallpaperService.init();
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (!WallpaperService.isInitialized)
        return;
      if (!root.started) {
        root.started = true;
        WallpaperService.currentWallpapers = {};
        WallpaperService.changeWallpaper(root.inputs + "/Motion.webp", root.monitor, "light");
        root.immediatePath = WallpaperService.getWallpaperPathForSlot(root.monitor, "light");
      }
      ++root.tick;
      if (root.tick === 20) {
        root.snapshot("valid");
        root.beforeFavorites = JSON.stringify(Settings.data.wallpaper.favorites);
        root.beforeTheme = JSON.stringify([Settings.data.colorSchemes.predefinedScheme, Settings.data.colorSchemes.darkMode, Settings.data.colorSchemes.useWallpaperColors, Settings.data.colorSchemes.generationMethod]);
        WallpaperService.changeWallpaper(root.inputs + "/Corrupt.webp", root.monitor, "light");
      } else if (root.tick === 40) {
        root.snapshot("invalid");
        WallpaperService.toggleFavorite(root.inputs + "/Missing.webp", "light", root.monitor);
      } else if (root.tick === 60) {
        root.snapshot("invalid-favorite");
        WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", root.monitor, "light");
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "light");
        WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", root.monitor, "light");
      } else if (root.tick === 80) {
        root.snapshot("latest");
        root.cancelled = WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "light", () => root.callbacks.push("cancelled"));
        if (root.cancelled && root.cancelled.cancel)
          root.cancelled.cancel();
      } else if (root.tick === 100) {
        root.snapshot("cancelled");
        WallpaperService.changeWallpaper(root.inputs + "/frame-0.png", "other-monitor", "light");
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "dark");
      } else if (root.tick === 120) {
        root.snapshot("independent");
        WallpaperService.toggleFavorite(root.inputs + "/Still.webp", "light", root.monitor);
      } else if (root.tick === 140) {
        root.snapshot("valid-favorite");
      } else if (root.tick >= 141 && !root.solidRequested && !root.pending) {
        root.solidRequested = true;
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "light");
        WallpaperService.setSolidColor("#123456");
      } else if (root.tick === 160) {
        root.snapshot("solid");
        backdrop.requestedWallpaperPath = "";
      } else if (root.tick >= 161 && !root.solidReasserted && !root.pending) {
        root.solidReasserted = true;
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "light");
        WallpaperService.setSolidColor("#123456");
      } else if (root.tick >= 180 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         snapshots: root.snapshots,
                                                         events: root.events,
                                                         callbacks: root.callbacks,
                                                         notices: root.notices,
                                                         immediatePath: root.immediatePath,
                                                         beforeFavorites: root.beforeFavorites,
                                                         beforeTheme: root.beforeTheme,
                                                         interests: ImageCacheService.sourceInterestCount,
                                                         requests: ImageCacheService.sourceRequestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning
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
