import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Background as Desktop
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string monitor: Quickshell.screens[0].name
  readonly property var transitions: ["none", "fade", "wipe", "disc", "stripes", "pixelate", "honeycomb"]
  property int tick: 0
  property int pending: 0
  property int phase: 0
  property int transitionIndex: 0
  property int completionFloor: 0
  property int requestedAt: 0
  property string expectedPath: ""
  readonly property bool redControl: Quickshell.env("IMAGE_DESKTOP_RED") === "1"
  // A plugin background root with the same per-screen contract (for example
  // parallax-wallpaper) replaces the shell's own background.
  readonly property string pluginRoot: Quickshell.env("IMAGE_DESKTOP_ROOT")
  property var snapshots: []
  property var completions: []
  property var afterCapture: null
  function desktop() {
    return background.item.instances[0].item;
  }
  function overview() {
    return overviewLoader.item.item.instances[0];
  }
  function visual(window) {
    for (var i = 0; i < window.contentItem.children.length; ++i) {
      var child = window.contentItem.children[i];
      if (child.visible && child.width > 0 && child.height > 0)
        return child;
    }
    return null;
  }
  function grab(item, name) {
    if (item && item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    })) {
      ++pending;
      return;
    }
    console.error("Wallpaper grab rejected: " + name);
    Qt.exit(3);
  }
  function request(path) {
    expectedPath = path;
    completionFloor = completions.length;
    requestedAt = tick;
    WallpaperService.wallpaperChanged(monitor, path);
  }
  function settled() {
    if (completions.length <= completionFloor)
      return false;
    var last = completions[completions.length - 1];
    var image = visual(overview());
    var overviewReady = image && (!("status" in image) || image.status === Image.Ready);
    return last.path === expectedPath && tick - last.tick >= 4 && !desktop().transitioning && overviewReady;
  }
  function requestTransition() {
    Settings.data.wallpaper.transitionType = [transitions[transitionIndex]];
    request(inputs + "/frame-" + (transitionIndex % 2 + 1) + ".png");
  }
  function snapshot(name) {
    var view = desktop();
    snapshots.push({
                     name: name,
                     transitioning: view.transitioning,
                     ready: view.wallpaperReady,
                     reason: view.errorReason || "",
                     current: view.currentWallpaper ? view.currentWallpaper.source : "",
                     result: view.currentWallpaper ? view.currentWallpaper.imageResult : {},
                     overview: {
                       path: overview().wallpaper,
                       cached: overview().preprocessedWallpaper,
                       image: visual(overview()) ? {
                                                     source: visual(overview()).source || "",
                                                     state: visual(overview()).imageState || "",
                                                     status: visual(overview()).status || 0,
                                                     width: visual(overview()).width,
                                                     height: visual(overview()).height
                                                   } : null
                     }
                   });
    grab(visual(view), name + "-desktop");
    grab(visual(overview()), name + "-overview");
  }
  function finish() {
    console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                     snapshots: root.snapshots,
                                                     completions: root.completions,
                                                     interests: ImageCacheService.sourceInterestCount,
                                                     requests: ImageCacheService.sourceRequestCount,
                                                     workerRunning: ImageCacheService.sourceWorkerRunning,
                                                     effective: {
                                                       overviewBlur: Settings.data.wallpaper.overviewBlur,
                                                       overviewTint: Settings.data.wallpaper.overviewTint,
                                                       transitionDuration: Settings.data.wallpaper.transitionDuration
                                                     }
                                                   }));
    Qt.quit();
  }
  Component {
    id: shellBackground
    Desktop.Background {}
  }
  Loader {
    id: background
    Component.onCompleted: {
      if (root.pluginRoot)
        setSource("file://" + root.pluginRoot, {
                    pluginApi: {
                      pluginSettings: {},
                      manifest: {
                        metadata: {
                          defaultSettings: {}
                        }
                      }
                    }
                  });
      else
        sourceComponent = shellBackground;
    }
  }
  Loader {
    id: overviewLoader
    sourceComponent: Desktop.Overview {
      active: true
    }
  }
  Connections {
    target: WallpaperService
    function onWallpaperProcessingComplete(screenName, path, cachedPath) {
      if (screenName !== root.monitor || root.tick < 5)
        return;
      var index = root.completions.length;
      root.completions.push({
                              path: path,
                              cached: cachedPath,
                              tick: root.tick,
                              transitioning: root.desktop().transitioning,
                              visible: root.desktop().visible
                            });
      // Verify the acknowledged wallpaper's pixels separately. A grab is
      // asynchronous and does not identify the buffer that triggered the signal.
      if (!root.redControl && root.desktop().visible)
        root.grab(root.visual(root.desktop()), "ack-" + index);
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    WallpaperService.init();
    Settings.data.wallpaper.transitionType = ["fade"];
    Settings.data.wallpaper.transitionDuration = 200;
    Settings.data.wallpaper.skipStartupTransition = true;
    Settings.data.wallpaper.overviewBlur = 0;
    Settings.data.wallpaper.overviewTint = 0;
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (!WallpaperService.isInitialized)
        return;
      ++root.tick;
      if (root.pending)
        return;
      if (root.afterCapture) {
        var next = root.afterCapture;
        root.afterCapture = null;
        next();
        return;
      }
      if (root.redControl && root.completions.length && root.tick - root.completions[0].tick >= 8) {
        root.snapshot("red-control");
        root.afterCapture = root.finish;
        return;
      }
      if (root.phase === 0 && root.tick >= 5) {
        root.phase = 1;
        root.request(root.inputs + "/Motion.webp");
      } else if (root.phase === 1 && root.settled()) {
        root.snapshot("valid");
        root.afterCapture = function () {
          root.phase = 2;
          root.request(root.inputs + "/Corrupt.webp");
        };
      } else if (root.phase === 2 && root.tick - root.requestedAt >= 12 && !root.desktop().transitioning) {
        root.snapshot("invalid");
        root.afterCapture = function () {
          root.phase = 3;
          root.request(root.inputs + "/frame-1.png");
          root.request(root.inputs + "/frame-2.png");
          root.request(root.inputs + "/Motion.webp");
        };
      } else if (root.phase === 3 && root.settled()) {
        root.snapshot("newest");
        root.afterCapture = function () {
          root.phase = 4;
          root.requestTransition();
        };
      } else if (root.phase === 4 && root.settled()) {
        root.snapshot(root.transitions[root.transitionIndex]);
        root.afterCapture = function () {
          ++root.transitionIndex;
          if (root.transitionIndex < root.transitions.length) {
            root.requestTransition();
          } else {
            root.phase = 5;
            root.request(WallpaperService.createSolidColorPath("#123456"));
          }
        };
      } else if (root.phase === 5 && root.settled()) {
        root.snapshot("solid");
        root.afterCapture = function () {
          root.phase = 6;
          root.request(root.inputs + "/Missing.webp");
        };
      } else if (root.phase === 6 && root.tick - root.requestedAt >= 12 && !root.desktop().transitioning) {
        root.snapshot("solid-invalid");
        root.afterCapture = function () {
          background.active = false;
          overviewLoader.active = false;
          root.phase = 7;
          root.requestedAt = root.tick;
        };
      } else if (root.phase === 7 && root.tick - root.requestedAt >= 3) {
        root.finish();
      }
    }
  }
  Timer {
    interval: 23000
    running: true
    onTriggered: Qt.exit(3)
  }
}
