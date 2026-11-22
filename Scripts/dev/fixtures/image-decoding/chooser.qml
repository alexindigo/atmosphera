import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.FileChooser
import qs.Services.Files
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int index: 0
  property int pending: 0
  property bool admitted: false
  property var tiles: []
  property var failures: []
  property var frames: []
  property int initialInterests: -1
  readonly property var names: ["Still.webp", "Motion.webp", "Still.avif", "Still.heic", "Multipage.tiff", "Misleading.png", "Corrupt.webp", "Missing.webp"]
  property bool done: false
  property bool advancing: false
  function grab(item, name) {
    ++pending;
    item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    });
  }
  FileThumbnails {
    id: provider
    enabled: root.admitted
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
                          modified: 1792260000000,
                          directory: false
                        })
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1100
    implicitHeight: 800
    color: "#202020"
    Repeater {
      id: entries
      model: ["grid", "compact", "list"]
      FileEntry {
        required property string modelData
        required property int index
        x: 0
        y: index * 180
        width: 570
        height: 170
        name: root.names[root.index]
        path: root.inputs + "/" + name
        directory: false
        bytes: 100
        modified: 1792260000000
        iconSize: 96
        compactMode: modelData === "compact"
        listMode: modelData === "list"
        columnWidths: [180, 80, 150]
        thumbnailProvider: provider
        thumbnailActive: root.admitted
      }
    }
    FileQuickLook {
      id: quicklook
      x: 600
      y: 0
      width: 500
      height: 750
      preview: previewData
      opened: root.admitted
    }
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 2) {
        root.initialInterests = ImageCacheService.sourceInterestCount;
        root.admitted = true;
      }
      if (root.advancing && !root.pending) {
        root.advancing = false;
        if (root.index + 1 === root.names.length)
          root.done = true;
        else
          ++root.index;
      }
      if (root.tick % 2 === 0 && root.tick >= 20 && root.tick <= 50 && quicklook.renderer) {
        root.frames.push({
                           frame: quicklook.renderer.frame,
                           atMs: Date.now()
                         });
        root.grab(quicklook.renderer, "quicklook-" + root.tick);
      }
      // Capture only settled frames, not the previous source's fade.
      if (root.tick >= 12 && root.tick % 7 === 0 && !root.done && !root.advancing) {
        var settled = true;
        for (var i = 0; i < entries.count; ++i) {
          var state = entries.itemAt(i).thumbnailState;
          if (!state.imageReady && !state.unavailable)
            settled = false;
        }
        if (settled || root.tick >= 90) {
          for (var j = 0; j < entries.count; ++j) {
            var entry = entries.itemAt(j);
            var name = "chooser-" + entry.modelData + "-" + root.names[root.index];
            var row = {
              id: name,
              state: entry.thumbnailState
            };
            if (root.index < 6) {
              root.tiles.push(row);
              root.grab(entry, name);
            } else {
              root.failures.push(row);
            }
          }
          root.advancing = true;
        }
      }
      if (root.done && root.tick >= 60 && !root.pending && root.admitted) {
        root.quickResult = {
          previewState: quicklook.renderer.previewState,
          frames: quicklook.renderer.frames
        };
        root.admitted = false;
      }
      if (root.done && !root.admitted && !root.pending && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         tiles: root.tiles,
                                                         failures: root.failures,
                                                         frames: root.frames,
                                                         quicklook: root.quickResult,
                                                         initialInterests: root.initialInterests,
                                                         kinds: ["a.heic", "a.jxl", "a.heif", "a.svgz"].map(name => FileTypes.previewKind(name)),
                                                         finalInterests: ImageCacheService.sourceInterestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning
                                                       }));
        Qt.quit();
      }
    }
  }
  property var quickResult: ({})
  Timer {
    interval: 22000
    running: true
    onTriggered: Qt.exit(3)
  }
}
