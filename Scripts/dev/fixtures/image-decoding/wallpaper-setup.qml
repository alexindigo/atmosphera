import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.SetupWizard
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int phase: 0
  property int pending: 0
  property var snapshots: []
  property var selections: []
  property var galleryFrames: []
  property var afterCapture: null
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  function find(item, accept) {
    if (accept(item))
      return item;
    for (var i = 0; item.children && i < item.children.length; ++i) {
      var child = find(item.children[i], accept);
      if (child)
        return child;
    }
    return null;
  }
  function grab(item, name) {
    ++pending;
    item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
      if (!root.pending && root.afterCapture) {
        var next = root.afterCapture;
        root.afterCapture = null;
        Qt.callLater(next);
      }
    });
  }
  function snapshot(name, after) {
    var setup = loader.item;
    var image = find(setup, item => "imagePath" in item && item.width > 300);
    var warning = find(setup, item => item.objectName === "wallpaperPreviewWarning");
    var point = warning ? warning.mapToItem(setup, 0, 0) : Qt.point(0, 0);
    snapshots.push({
                     name: name,
                     selected: setup.selectedWallpaper,
                     cached: setup.previewCachedPath,
                     state: "previewState" in setup ? setup.previewState : "",
                     reason: "errorReason" in setup ? setup.errorReason : "",
                     warning: warning ? {
                                          x: point.x,
                                          y: point.y,
                                          width: warning.width,
                                          height: warning.height,
                                          visible: warning.visible
                                        } : null,
                     image: image ? {
                                      status: image.status,
                                      result: image.imageResult
                                    } : null
                   });
    afterCapture = after || null;
    grab(image, name);
    grab(setup, name + "-screen");
  }
  FloatingWindow {
    visible: true
    implicitWidth: 600
    implicitHeight: 640
    color: "#202020"
    Loader {
      id: loader
      anchors.fill: parent
      sourceComponent: SetupWallpaperStep {
        onWallpaperChanged: path => root.selections.push(path)
      }
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    Qt.callLater(function () {
      loader.item.selectedWallpaper = root.inputs + "/Motion.webp";
    });
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (root.pending || root.afterCapture)
        return;
      ++root.tick;
      var setup = loader.item;
      if (!setup && root.phase < 7)
        return;
      var image = setup ? root.find(setup, item => "imagePath" in item && item.width > 300) : null;
      var presented = setup && setup.previewState === "ready" && setup.previewCachedPath !== "" && image && image.status === Image.Ready;
      var failed = setup && setup.previewState === "unavailable" && image && image.status === Image.Ready;
      if (root.phase === 0 && presented) {
        root.phase = 1;
        root.snapshot("before", function () {
          loader.item.selectedWallpaper = root.inputs + "/Corrupt.webp";
        });
      } else if (root.phase === 1 && failed) {
        root.phase = 2;
        root.snapshot("failed", function () {
          loader.item.selectedWallpaper = root.inputs + "/frame-2.png";
          loader.item.selectedWallpaper = root.inputs + "/frame-1.png";
        });
      } else if (root.phase === 2 && presented && setup.previewCachedPath !== root.snapshots[0].cached) {
        root.phase = 3;
        root.snapshot("latest", function () {
          if (loader.item.selectWallpaper)
            loader.item.selectWallpaper(root.inputs + "/Corrupt.webp");
        });
      } else if (root.phase === 3 && failed) {
        root.phase = 4;
        root.snapshot("invalid-intent", function () {
          if (loader.item.selectWallpaper)
            loader.item.selectWallpaper(root.inputs + "/Still.webp");
        });
      } else if (root.phase === 4 && presented && setup.previewCachedPath !== root.snapshots[2].cached && root.selections.length > 0) {
        root.phase = 5;
        root.snapshot("valid-intent", function () {
          loader.item.filteredWallpapers = [root.inputs + "/Motion.webp", root.inputs + "/Corrupt.webp"];
        });
      } else if (root.phase === 5) {
        var thumb = root.find(loader.item, item => "imagePath" in item && item.imagePath.endsWith("Motion.webp") && item.width < 300);
        if (thumb && thumb.status === Image.Ready) {
          root.galleryFrames.push({
                                    status: thumb.status,
                                    result: thumb.imageResult
                                  });
          root.grab(thumb, "gallery-" + (114 + root.galleryFrames.length));
          if (root.galleryFrames.length === 11)
            root.phase = 6;
        }
      } else if (root.phase === 6) {
        loader.active = false;
        root.phase = 7;
        root.tick = 0;
      } else if (root.phase === 7 && root.tick >= 15 && !ImageCacheService.sourceInterestCount && !ImageCacheService.sourceRequestCount && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         snapshots: root.snapshots,
                                                         selections: root.selections,
                                                         galleryFrames: root.galleryFrames,
                                                         interests: ImageCacheService.sourceInterestCount,
                                                         requests: ImageCacheService.sourceRequestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning,
                                                         warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 22000
    running: true
    onTriggered: {
      console.log("IMAGE_TIMEOUT|" + JSON.stringify({
                                                      phase: root.phase,
                                                      tick: root.tick,
                                                      pending: root.pending,
                                                      state: loader.item ? loader.item.previewState : "destroyed"
                                                    }));
      Qt.exit(3);
    }
  }
}
