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
  property int tick: 0
  property int pending: 0
  property bool started: false
  property var events: []
  property var notices: []
  property var completions: []
  property var callbacks: []
  function grab(name) {
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
      ++root.tick;
      if (root.tick === 10) {
        root.grab("before");
        WallpaperService.changeWallpaper(root.inputs + "/Motion.webp", root.monitor, "light", (success, names, detail) => root.callbacks.push({
                                                                                                                                                success: success,
                                                                                                                                                detail: detail
                                                                                                                                              }));
      } else if (root.tick === 30) {
        WallpaperService.toggleFavorite(root.inputs + "/Still.webp", "light", root.monitor);
      } else if (root.tick === 50) {
        root.grab("after");
      } else if (root.tick === 60) {
        backdrop.requestedWallpaperPath = "";
      } else if (root.tick >= 70 && !root.pending) {
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
    onTriggered: Qt.exit(3)
  }
}
