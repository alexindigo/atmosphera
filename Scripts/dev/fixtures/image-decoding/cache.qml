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
  property bool idleBeforeAdmission: false
  property var rows: []
  property var raw: ({})
  function idle() {
    return ordinary.status === Image.Null && !ordinary.outputUrl && [0, 1, 2].every(i => {
      const entry = entries.itemAt(i);
      return entry && entry.thumbnailState.state === "idle";
    });
  }
  function grab(item, name) {
    if (!item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    })) {
      console.error("Cache grab rejected: " + name);
      Qt.exit(4);
      return false;
    }
    ++pending;
    return true;
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
        root.idleBeforeAdmission = root.idle();
        root.admitted = true;
      }
      if (root.tick >= 12 && !root.captured && ordinary.imageState === "ready") {
        for (var i = 0; i < entries.count; ++i) {
          var candidate = entries.itemAt(i);
          if (!candidate || (!candidate.previewUnavailable && (!candidate.thumbnailState.imageReady || candidate.thumbnailState.reveal < 1)))
            return;
        }
        root.captured = true;
        root.raw = {
          state: ordinary.imageState,
          result: ordinary.imageResult
        };
        if (!root.grab(ordinary, "ordinary"))
          return;
        for (var j = 0; j < entries.count; ++j) {
          var entry = entries.itemAt(j);
          root.rows.push({
                           name: entry.name,
                           state: entry.thumbnailState
                         });
          if (!root.grab(entry, "thumbnail-" + j))
            return;
        }
      }
      if (root.captured && !root.pending && root.admitted)
        root.admitted = false;
      if (root.captured && !root.pending && !root.admitted && root.idle()) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         rows: root.rows,
                                                         ordinary: root.raw,
                                                         idleBeforeAdmission: root.idleBeforeAdmission,
                                                         idleAfterRetirement: root.idle()
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
