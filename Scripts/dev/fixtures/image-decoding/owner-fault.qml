pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  property var first: null
  property int deliveries: 0
  property int failedTicks: 0
  property bool retryStarted: false
  property bool grabbing: false
  property var retryResult: null

  FloatingWindow {
    visible: true
    implicitWidth: 192
    implicitHeight: 128
    NImage {
      id: retryImage
      anchors.fill: parent
      source: root.inputs + "/Retry.webp"
      onImageStateChanged: {
        if (imageState === "unavailable") {
          ++root.deliveries;
          if (!root.first)
            root.first = {
              state: imageState,
              code: errorCode,
              reason: errorReason,
              url: outputUrl,
              generation: generation
            };
        }
      }
    }
  }
  Process {
    id: repair
    command: ["mv", "--", root.inputs + "/Retry-replacement.webp", retryImage.source]
    onExited: code => {
      if (code !== 0) {
        Qt.exit(3);
        return;
      }
      root.retryStarted = true;
      retryImage.retry();
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (!root.retryStarted && retryImage.imageState === "unavailable" && ++root.failedTicks === 5)
        repair.running = true;
      if (root.retryStarted && !root.grabbing && retryImage.status === Image.Ready) {
        root.grabbing = true;
        root.retryResult = {
          state: retryImage.imageState,
          generation: retryImage.generation
        };
        if (!retryImage.grabToImage(result => {
          const saved = result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/retry.png");
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       name: "retry",
                                                       saved: saved
                                                     }));
          retryImage.active = false;
        }))
          Qt.exit(3);
      }
      if (!retryImage.active && retryImage.imageState === "idle") {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         first: root.first,
                                                         deliveries: root.deliveries,
                                                         retry: root.retryResult,
                                                         finalState: retryImage.imageState,
                                                         finalUrl: retryImage.outputUrl
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    running: true
    interval: 15000
    onTriggered: Qt.exit(2)
  }
}
