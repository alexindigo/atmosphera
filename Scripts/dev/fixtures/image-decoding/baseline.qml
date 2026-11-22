import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.FileChooser
import qs.Modules.Panels.SetupWizard
import qs.Services.Files
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int pendingGrabs: 0
  property var samples: []
  property var nativeEvents: []
  property var conversion: ({
                              called: false
                            })
  property var completions: []

  function grab(item, name) {
    ++pendingGrabs;
    if (!item.grabToImage(result => {
      var saved = result.saveToFile(output + "/" + name + ".png");
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: saved
                                                 }));
      --root.pendingGrabs;
    })) {
      --pendingGrabs;
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: false
                                                 }));
    }
  }

  QtObject {
    id: previewData
    property string path: root.inputs + "/Motion.webp"
    property string kind: FileTypes.previewKind("Motion.webp")
    property string status: "ready"
    property string errorText: ""
    property string text: ""
    property bool truncated: false
    property bool pdfAvailable: false
    property var item: ({
                          name: "Motion.webp",
                          size: 100,
                          modified: new Date(1792260000000),
                          directory: false
                        })
  }

  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 1024
    implicitHeight: 720
    color: "#202020"
    Image {
      id: png
      x: 0
      y: 0
      width: 96
      height: 64
      source: "file://" + root.inputs + "/frame-0.png"
    }
    Image {
      id: webp
      x: 110
      y: 0
      width: 96
      height: 64
      source: "file://" + root.inputs + "/Still.webp"
    }
    AnimatedImage {
      id: motion
      x: 220
      y: 0
      width: 96
      height: 64
      source: "file://" + root.inputs + "/Motion.webp"
      playing: true
      onCurrentFrameChanged: root.nativeEvents.push({
                                                      frame: currentFrame,
                                                      atMs: Date.now()
                                                    })
    }
    FileEntryArtwork {
      id: pngTile
      x: 0
      y: 90
      width: 128
      height: 96
      name: "frame-0.png"
      path: root.inputs + "/frame-0.png"
      directory: false
      modified: 1792260000000
      descriptor: FileTypes.artwork(name, false, path)
      thumbnailActive: true
    }
    FileEntryArtwork {
      id: webpTile
      x: 150
      y: 90
      width: 128
      height: 96
      name: "Still.webp"
      path: root.inputs + "/Still.webp"
      directory: false
      modified: 1792260000000
      descriptor: FileTypes.artwork(name, false, path)
      thumbnailActive: true
    }
    FileQuickLook {
      id: quicklook
      x: 0
      y: 220
      width: 500
      height: 470
      preview: previewData
      opened: true
    }
    SetupWallpaperStep {
      id: setup
      x: 530
      y: 90
      width: 470
      height: 600
    }
  }

  Connections {
    target: ImageCacheService
    function onProcessingComplete(key, path) {
      root.completions.push({
                              key: key,
                              path: path
                            });
    }
    function onInitializedChanged() {
      if (!ImageCacheService.initialized)
        return;
      ImageCacheService.getThumbnail(root.inputs + "/Motion.webp", (path, success) => {
        root.conversion = {
          called: true,
          path: path,
          success: success
        };
      });
      setup.selectedWallpaper = root.inputs + "/Motion.webp";
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick % 2 === 0) {
        root.samples.push({
                            tick: root.tick,
                            nativeFrame: motion.currentFrame,
                            quickFrame: quicklook.renderer && quicklook.renderer.frame !== undefined ? quicklook.renderer.frame : -1,
                            quickFrames: quicklook.renderer && quicklook.renderer.frames !== undefined ? quicklook.renderer.frames : 0
                          });
      }
      if (root.tick === 15) {
        root.grab(png, "raw-png");
        root.grab(webp, "raw-webp");
        root.grab(pngTile, "chooser-png");
        root.grab(webpTile, "chooser-webp");
        root.grab(setup, "setup-wallpaper");
      }
      if ([16, 18, 20, 22, 24, 26, 28, 30].includes(root.tick) && quicklook.renderer)
        root.grab(quicklook.renderer, "quicklook-" + root.tick);
      if (root.tick >= 40 && root.pendingGrabs === 0) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         png: png.status,
                                                         webp: webp.status,
                                                         motion: motion.status,
                                                         frames: motion.frameCount,
                                                         pngTile: pngTile.thumbnailState,
                                                         webpTile: webpTile.thumbnailState,
                                                         quicklook: quicklook.renderer ? quicklook.renderer.previewState : "missing",
                                                         setup: {
                                                           source: setup.selectedWallpaper,
                                                           cached: setup.previewCachedPath
                                                         },
                                                         conversion: root.conversion,
                                                         completions: root.completions,
                                                         samples: root.samples,
                                                         nativeEvents: root.nativeEvents
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(3)
  }
}
