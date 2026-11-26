pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string media: Quickshell.env("IMAGE_FIXTURES") + "/Rotated.mp4"
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property string exportPath: ""
  property var request: null
  property bool capturing: false

  FloatingWindow {
    implicitWidth: 180
    implicitHeight: 160
    Row {
      id: preview
      anchors.centerIn: parent
      NImage {
        id: live
        width: 90
        height: 160
        source: root.media
        sourceSize: Qt.size(90, 160)
      }
      NImage {
        id: exported
        width: 90
        height: 160
        source: root.exportPath
        sourceSize: Qt.size(90, 160)
      }
    }
    Timer {
      interval: 50
      running: true
      repeat: true
      onTriggered: {
        if (root.capturing || live.imageState !== "ready" || exported.imageState !== "ready")
          return;
        root.capturing = true;
        if (!preview.grabToImage(result => {
          const saved = result.saveToFile(root.output + "/video.png");
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       saved: saved
                                                     }));
          console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                           width: live.decodedSize.width,
                                                           height: live.decodedSize.height,
                                                           exportWidth: exported.decodedSize.width,
                                                           exportHeight: exported.decodedSize.height,
                                                           exported: root.exportPath,
                                                           generated: ImageCacheService.isGeneratedImage(root.exportPath)
                                                         }));
          Qt.quit();
        }, Qt.size(180, 160)))
          Qt.exit(5);
      }
    }
  }

  Component.onCompleted: {
    request = ImageCacheService.exportVideoFrame(media, (path, ok, reply) => {
      root.request = null;
      if (!ok) {
        console.error("Export failed:", JSON.stringify(reply));
        Qt.exit(4);
      } else {
        root.exportPath = path;
      }
    });
  }
  Component.onDestruction: request?.cancel()
  Timer {
    interval: 15000
    running: true
    onTriggered: Qt.exit(6)
  }
}
