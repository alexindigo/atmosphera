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
  property int phase: 0
  property int pending: 0
  property bool started: false
  property var events: []
  property var notices: []
  property var completions: []
  property var callbacks: []
  function grab(name, afterCapture) {
    ++pending;
    backdrop.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
      if (afterCapture)
        afterCapture();
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
      fallbackColor: "#000000"
    }
  }
  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      root.events.push({
                         screen: screenName,
                         path: path
                       });
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices.push({
                          title: title,
                          reason: description,
                          type: type
                        });
    }
  }
  Connections {
    target: ImageCacheService
    function onProcessingComplete(key, path) {
      root.completions.push(path);
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
        var seed = {};
        seed[root.monitor] = {
          light: root.inputs + "/frame-0.png",
          dark: root.inputs + "/frame-0.png"
        };
        WallpaperService.currentWallpapers = seed;
        backdrop.requestCachedWallpaper();
      }
      if (root.phase === 0 && backdrop.imageState === "ready" && !root.pending) {
        root.phase = 1;
        root.grab("before", function () {
          WallpaperService.changeWallpaper(root.inputs + "/Motion.webp", root.monitor, "light", (success, names, detail) => root.callbacks.push({
                                                                                                                                                  success: success,
                                                                                                                                                  detail: detail
                                                                                                                                                }));
          root.phase = 2;
        });
      } else if (root.phase === 2 && root.callbacks.length === 1) {
        root.phase = 3;
        WallpaperService.toggleFavorite(root.inputs + "/Still.webp", "light", root.monitor);
      } else if (root.phase === 3 && root.notices.length === 2 && !root.pending) {
        root.phase = 4;
        root.grab("after", function () {
          backdrop.requestedWallpaperPath = "";
          root.phase = 5;
        });
      } else if (root.phase === 5 && !root.pending && ImageCacheService.sourceInterestCount === 0 && ImageCacheService.sourceRequestCount === 0 && !ImageCacheService.sourceWorkerRunning) {
        root.phase = 6;
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         path: WallpaperService.getWallpaper(root.monitor),
                                                         events: root.events,
                                                         notices: root.notices,
                                                         completions: root.completions,
                                                         callbacks: root.callbacks,
                                                         favorites: Settings.data.wallpaper.favorites,
                                                         interests: ImageCacheService.sourceInterestCount,
                                                         requests: ImageCacheService.sourceRequestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 20000
    running: true
    onTriggered: {
      console.log("IMAGE_TIMEOUT|" + JSON.stringify({
                                                      phase: root.phase,
                                                      callbacks: root.callbacks.length,
                                                      notices: root.notices.length,
                                                      imageState: backdrop.imageState,
                                                      interests: ImageCacheService.sourceInterestCount,
                                                      requests: ImageCacheService.sourceRequestCount,
                                                      worker: ImageCacheService.sourceWorkerRunning
                                                    }));
      Qt.exit(3);
    }
  }
}
