import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.FileChooser
import qs.Services.Files
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property bool admitted: false
  property int tick: 0
  property int pending: 0
  property bool captured: false
  property int idleInterests: -1
  property var rows: []
  property var raw: ({})
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
  FloatingWindow {
    visible: true
    implicitWidth: 500
    implicitHeight: 150
    color: "#202020"
    Repeater {
      id: entries
      model: ["Still.webp", "Foreign16.webp", "ForeignInterlaced.webp"]
      FileEntryArtwork {
        required property string modelData
        required property int index
        x: index * 100
        width: 64
        height: 64
        name: modelData
        path: root.inputs + "/" + name
        directory: false
        modified: "foreign-cache"
        descriptor: FileTypes.artwork(name, directory, path)
        thumbnailActive: root.admitted
      }
    }
    NImage {
      id: ordinary
      x: 350
      width: 64
      height: 64
      source: root.inputs + "/Still.webp"
      active: root.admitted
    }
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 2) {
        root.idleInterests = ImageCacheService.sourceInterestCount;
        root.admitted = true;
      }
      if (root.tick >= 12 && !root.captured && ordinary.imageState === "ready") {
        for (var i = 0; i < entries.count; ++i) {
          if (!entries.itemAt(i).thumbnailState.imageReady && !entries.itemAt(i).previewUnavailable)
            return;
        }
        root.captured = true;
        root.raw = {
          state: ordinary.imageState,
          result: ordinary.imageResult
        };
        root.grab(ordinary, "ordinary");
        for (var j = 0; j < entries.count; ++j) {
          var entry = entries.itemAt(j);
          root.rows.push({
                           name: entry.name,
                           state: entry.thumbnailState
                         });
          root.grab(entry, "thumbnail-" + j);
        }
      }
      if (root.captured && !root.pending && root.admitted)
        root.admitted = false;
      if (root.captured && !root.pending && !root.admitted && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         rows: root.rows,
                                                         ordinary: root.raw,
                                                         idleInterests: root.idleInterests,
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
