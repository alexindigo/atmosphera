import QtQuick
import Quickshell
import qs.Services.Files
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property int tick: 0
  property int pending: 0
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
      onStatusChanged: {
        if (status !== Image.Ready || root.retiring)
          return;
        root.survivor = {
          ready: true,
          result: second.result,
          firstUrl: first.url,
          ffmpeg: secondPicker.statistics.ffmpeg
        };
        ++root.pending;
        grabToImage(result => {
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       name: "survivor",
                                                       saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/survivor.png")
                                                     }));
          --root.pending;
          root.retiring = true;
          second.active = false;
        });
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 3) {
        root.shared = {
          interests: ImageCacheService.sourceInterestCount,
          requests: ImageCacheService.sourceRequestCount
        };
        first.active = false;
        firstPicker.enabled = false;
      }
      if (root.retiring && !root.pending && !ImageCacheService.sourceWorkerRunning) {
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
