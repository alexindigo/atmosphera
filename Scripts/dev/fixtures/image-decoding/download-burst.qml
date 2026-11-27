import QtQuick
import Quickshell
import qs.Widgets

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("IMAGE_BURST_URL")
  property bool started: false
  property int tick: 0
  property var cancelled: []
  property string failure: ""
  property bool captured: false

  FloatingWindow {
    visible: true
    implicitWidth: 120
    implicitHeight: 80
    NImage {
      id: kept
      width: 96
      height: 64
      source: root.base + "/ready"
    }
    NImage {
      id: failed
      width: 1
      height: 1
      active: !root.started
      source: root.base + "/truncated"
    }
    Repeater {
      id: burst
      model: root.started ? Number(Quickshell.env("IMAGE_BURST_SIZE")) : 0
      NImage {
        required property int index
        width: 1
        height: 1
        active: !root.cancelled.includes(index)
        source: root.base + "/hold/" + index
      }
    }
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      if (!root.started) {
        if (kept.imageState === "ready" && failed.imageState === "unavailable") {
          root.failure = failed.errorCode;
          root.started = true;
        }
        return;
      }
      ++root.tick;
      if (root.tick === 20)
        root.cancelled = [0, 4]; // one admitted transfer and one queued request
      if (root.tick === 40 && !kept.grabToImage(result => {
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/kept.png")
                                                   }));
        root.captured = true;
      }))
        Qt.exit(3);
      if (root.tick >= 45 && root.captured) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         kept: kept.imageState,
                                                         failure: root.failure,
                                                         cancelled: root.cancelled.map(index => burst.itemAt(index).imageState),
                                                         rejected: Array.from({
                                                                                length: burst.count
                                                                              }, (_, index) => burst.itemAt(index).errorCode).filter(code => code === "download-busy").length
                                                       }));
        // Quit with both admitted transfers still in flight.
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
