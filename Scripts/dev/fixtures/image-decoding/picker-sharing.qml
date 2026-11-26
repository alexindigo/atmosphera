import QtQuick
import Quickshell
import qs.Services.Files
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property bool firstReleased: false
  property bool grabbing: false
  property var shared: ({})
  property var survivor: ({})
  property bool retiring: false
  FileThumbnails {
    id: firstPicker
  }
  FileThumbnails {
    id: secondPicker
  }
  FileThumbnail {
    id: first
    provider: firstPicker
    path: Quickshell.env("IMAGE_FIXTURES") + "/Shared.mp4"
    active: true
    pixels: 128
    stamp: "one"
  }
  FileThumbnail {
    id: second
    provider: secondPicker
    path: first.path
    active: true
    pixels: first.pixels
    stamp: first.stamp
  }
  FloatingWindow {
    visible: true
    implicitWidth: 192
    implicitHeight: 128
    color: "transparent"
    NImage {
      id: image
      anchors.fill: parent
      source: second.url
      active: second.active
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (!root.firstReleased && firstPicker.running && secondPicker.running && ImageCacheService.sourceInterestCount === 2 && ImageCacheService.sourceRequestCount === 1) {
        root.shared = {
          interests: ImageCacheService.sourceInterestCount,
          requests: ImageCacheService.sourceRequestCount
        };
        root.firstReleased = true;
        first.active = false;
        firstPicker.enabled = false;
      }
      // The image itself can acquire an interest after the thumbnail arrives.
      // Observe the retired picker's ownership, not a global cardinality.
      if (root.firstReleased && !root.grabbing && !firstPicker.running && secondPicker.running && image.status === Image.Ready) {
        root.grabbing = true;
        root.survivor = {
          ready: true,
          result: second.result,
          firstUrl: first.url,
          videoFrame: secondPicker.statistics.videoFrame
        };
        if (!image.grabToImage(result => {
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       name: "survivor",
                                                       saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/survivor.png")
                                                     }));
          root.retiring = true;
          second.active = false;
        })) {
          console.error("Picker survivor grab rejected");
          Qt.exit(3);
        }
      }
      if (root.retiring && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         shared: root.shared,
                                                         survivor: root.survivor,
                                                         finalInterests: ImageCacheService.sourceInterestCount,
                                                         finalRequests: ImageCacheService.sourceRequestCount,
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
