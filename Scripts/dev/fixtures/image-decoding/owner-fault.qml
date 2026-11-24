import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property string token: ""
  property var first: ({})
  property int deliveries: 0
  property bool retryStarted: false
  property bool saved: false
  property var retryResult: ({})
  FloatingWindow {
    visible: true
    implicitWidth: 192
    implicitHeight: 128
    NImage {
      id: retryImage
      anchors.fill: parent
      active: false
      source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp"
      sourceSize: Qt.size(192, 128)
      normalize: true
    }
  }
  Component.onCompleted: {
    token = ImageCacheService.acquireSource({
                                              source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp",
                                              width: 192,
                                              height: 128,
                                              animationIntent: "still",
                                              fit: "contain"
                                            }, function (reply) {
                                              ++root.deliveries;
                                              root.first = reply;
                                              ImageCacheService.releaseSource(root.token);
                                              root.token = "";
                                              retryImage.active = true;
                                            });
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (retryImage.active && !root.retryStarted && retryImage.imageState === "ready" && retryImage.status === Image.Ready) {
        root.retryStarted = true;
        root.retryResult = {
          state: retryImage.imageState,
          result: retryImage.imageResult
        };
        if (!retryImage.grabToImage(result => {
          root.saved = result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/retry.png");
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       name: "retry",
                                                       saved: root.saved
                                                     }));
          retryImage.active = false;
        })) {
          console.error("Owner retry grab rejected");
          Qt.exit(3);
        }
      }
      if (root.retryStarted && !retryImage.active && ImageCacheService.sourceInterestCount === 0 && ImageCacheService.sourceRequestCount === 0 && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         first: root.first,
                                                         deliveries: root.deliveries,
                                                         retry: root.retryResult,
                                                         saved: root.saved,
                                                         finalInterests: ImageCacheService.sourceInterestCount,
                                                         finalRequests: ImageCacheService.sourceRequestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning
                                                       }));
        Qt.quit();
      }
    }
  }
}
