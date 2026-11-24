import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Wallpaper
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string url: Quickshell.env("IMAGE_REMOTE_URL")
  readonly property string monitor: Quickshell.screens[0].name
  readonly property var modelData: Quickshell.screens[0]
  property int tick: 0
  property int pending: 0
  property var snapshots: []
  property var downloads: []
  property var callbacks: []
  property var notices: []
  property string initialPath: ""
  property string capturedDirectory: ""
  property bool immediatePublication: false
  property int rawStatus: 0
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  function select(name, target) {
    return panel.contentItem.wallhavenView.wallhavenDownloadAndApply({
                                                                       id: name,
                                                                       path: url + "/" + name + ".jpg"
                                                                     }, target);
  }
  function snapshot(name, afterCapture) {
    snapshots.push({
                     name: name,
                     path: WallpaperService.getWallpaperPathForSlot(monitor, "light"),
                     dark: WallpaperService.getWallpaperPathForSlot(monitor, "dark"),
                     other: WallpaperService.getWallpaperPathForSlot("other-monitor", "light"),
                     otherDark: WallpaperService.getWallpaperPathForSlot("other-monitor", "dark"),
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
      if (afterCapture)
        afterCapture();
    });
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    WallpaperPanel {
      id: panel
      screen: Quickshell.screens[0]
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
    }
    Image {
      id: raw
      visible: false
      source: root.inputs + "/Still.webp"
    }
  }
  Connections {
    target: WallhavenService
    function onWallpaperDownloaded(wallpaperId, localPath) {
      root.downloads.push({
                            id: wallpaperId,
                            path: localPath
                          });
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices.push({
                          tick: root.tick,
                          type: type,
                          reason: description
                        });
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    WallpaperService.init();
    Settings.data.wallpaper.linkLightAndDarkWallpapers = false;
    Settings.data.wallpaper.setWallpaperOnAllMonitors = false;
    Settings.data.general.animationDisabled = true;
    Qt.callLater(() => panel.open());
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      if (!WallpaperService.isInitialized || (!root.tick && !panel.contentItem))
        return;
      ++root.tick;
      if (root.tick === 1) {
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", root.monitor, "dark");
        WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", root.monitor, "light");
        WallpaperService.changeWallpaper(root.inputs + "/frame-2.png", "other-monitor", "light");
      } else if (root.tick === 15) {
        root.initialPath = WallpaperService.getWallpaperPathForSlot(root.monitor, "light");
        root.capturedDirectory = root.inputs + "/retained ' [0] : images";
        Settings.data.wallpaper.directory = root.capturedDirectory;
        WallpaperService.wallpaperSelectionAppearance = "light";
        root.select("motion");
        root.immediatePublication = WallpaperService.getWallpaperPathForSlot(root.monitor, "light") !== root.initialPath;
        Settings.data.wallpaper.directory = root.inputs + "/later-directory";
        Settings.data.wallpaper.setWallpaperOnAllMonitors = true;
        WallpaperService.wallpaperSelectionAppearance = "dark";
      } else if (root.tick === 45) {
        root.snapshot("remote");
        WallpaperService.wallpaperSelectionAppearance = "light";
        root.select("bad", root.monitor);
      } else if (root.tick === 65) {
        root.snapshot("invalid");
        root.select("slow", root.monitor);
      } else if (root.tick === 67) {
        WallpaperService.changeWallpaper(root.inputs + "/frame-1.png", root.monitor, "light");
      } else if (root.tick === 90) {
        root.snapshot("superseded");
        WallhavenService.downloadWallpaper({
                                             id: "standalone",
                                             path: root.url + "/motion.jpg"
                                           }, function (success, path, detail) {
                                             root.callbacks.push({
                                                                   id: "standalone",
                                                                   success: success,
                                                                   path: path,
                                                                   detail: detail
                                                                 });
                                           });
        WallhavenService.downloadWallpaper({
                                             id: "invalid",
                                             path: root.url + "/bad.jpg"
                                           }, function (success, path, detail) {
                                             root.callbacks.push({
                                                                   id: "invalid",
                                                                   success: success,
                                                                   path: path,
                                                                   detail: detail
                                                                 });
                                           });
        var cancelled = WallhavenService.downloadWallpaper({
                                                             id: "cancelled",
                                                             path: root.url + "/slow.jpg"
                                                           }, function (success, path) {
                                                             root.callbacks.push({
                                                                                   id: "cancelled",
                                                                                   success: success,
                                                                                   path: path
                                                                                 });
                                                           });
        cancelled.cancel();
      } else if (root.tick === 115) {
        WallpaperService.wallpaperSelectionAppearance = "dark";
        root.select("motion", "other-monitor");
        WallpaperService.wallpaperSelectionAppearance = "light";
      } else if (root.tick === 140) {
        root.snapshot("independent");
        root.select("missing", root.monitor);
      } else if (root.tick === 165) {
        root.rawStatus = raw.status;
        root.snapshot("http-failed", function () {
          backdrop.requestedWallpaperPath = "";
          panel.close();
        });
      } else if (root.tick >= 180 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         snapshots: root.snapshots,
                                                         downloads: root.downloads,
                                                         callbacks: root.callbacks,
                                                         notices: root.notices,
                                                         initialPath: root.initialPath,
                                                         capturedDirectory: root.capturedDirectory,
                                                         immediatePublication: root.immediatePublication,
                                                         raw: root.rawStatus,
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
