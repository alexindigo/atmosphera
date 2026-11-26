import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.FileChooser
import qs.Services.Files

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int index: 0
  property int pending: 0
  property bool admitted: false
  property int sourceTick: 0
  property var tiles: []
  property var failures: []
  property var frames: []
  property int quickStart: -1
  readonly property int quickSpan: 30
  property var inactive: []
  readonly property var names: ["Still.webp", "Motion.webp", "Still.avif", "Still.heic", "Multipage.tiff", "Misleading.png", "Corrupt.webp", "Missing.webp", "Large.mp4", "Still.webp"]
  property bool done: false
  property bool advancing: false
  function grab(item, name) {
    if (!item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    })) {
      console.error("CHOOSER_GRAB_REJECTED|" + name);
      Qt.exit(2);
      return;
    }
    ++pending;
  }
  function presentations() {
    return Array.from({
                        length: entries.count
                      }, (_, i) => entries.itemAt(i).thumbnailState);
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
      if (!root.admitted && !root.done && root.presentations().every(state => state.state === "idle")) {
        root.inactive = root.presentations();
        root.admitted = true;
        root.sourceTick = root.tick;
      }
      if (root.advancing && !root.pending) {
        root.advancing = false;
        if (root.index + 1 === root.names.length)
          root.done = true;
        else {
          ++root.index;
          root.sourceTick = root.tick;
        }
      }
      const renderer = quicklook.renderer;
      const ready = renderer && renderer.previewState === "ready";
      if (ready && root.quickStart < 0)
        root.quickStart = root.tick;
      const elapsed = root.tick - root.quickStart;
      if (ready && elapsed <= root.quickSpan && elapsed % 2 === 0) {
        root.frames.push({
                           playing: renderer.playing,
                           atMs: Date.now()
                         });
        root.grab(renderer, "quicklook-" + root.tick);
      }
      // Capture only settled frames, not the previous source's fade.
      if (root.admitted && root.tick >= 12 && root.tick % 7 === 0 && !root.done && !root.advancing) {
        var settled = true;
        for (var i = 0; i < entries.count; ++i) {
          var state = entries.itemAt(i).thumbnailState;
          if ((!state.imageReady || state.reveal < 1) && !state.unavailable)
            settled = false;
        }
        if (settled || root.tick - root.sourceTick >= 90) {
          for (var j = 0; j < entries.count; ++j) {
            var entry = entries.itemAt(j);
            var name = "chooser-" + entry.modelData + "-" + (root.index === root.names.length - 1 ? "recovered-" : "") + root.names[root.index];
            var row = {
              id: name,
              state: entry.thumbnailState
            };
            if (entry.name !== "Corrupt.webp" && entry.name !== "Missing.webp") {
              root.tiles.push(row);
              root.grab(entry, name);
            } else {
              root.failures.push(row);
            }
          }
          root.advancing = true;
        }
      }
      if (root.done && root.quickStart >= 0 && elapsed > root.quickSpan && !root.pending && root.admitted) {
        root.quickResult = {
          previewState: renderer?.previewState,
          frames: renderer?.frames
        };
        root.admitted = false;
      }
      if (root.done && !root.admitted && !root.pending && !quicklook.renderer && root.presentations().every(state => state.state === "idle")) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         tiles: root.tiles,
                                                         failures: root.failures,
                                                         frames: root.frames,
                                                         quicklook: root.quickResult,
                                                         inactive: root.inactive,
                                                         kinds: ["a.heic", "a.jxl", "a.heif", "a.svgz"].map(name => FileTypes.previewKind(name)),
                                                         retired: root.presentations()
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
