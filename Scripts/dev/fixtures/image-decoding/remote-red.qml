import QtQuick
import Quickshell
import qs.Services.UI

ShellRoot {
  id: root
  property var result: ({})
  property bool done: false
  FloatingWindow {
    visible: true
    implicitWidth: 96
    implicitHeight: 64
    // This historical control must also load on shells predating NImage.
    Image {
      id: image
      anchors.fill: parent
      source: root.result.path ? "file://" + root.result.path : ""
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    WallhavenService.downloadWallpaper({
                                         id: "invalid",
                                         path: Quickshell.env("IMAGE_REMOTE_URL") + "/bad.jpg"
                                       }, function (success, path) {
                                         root.result = {
                                           success: success,
                                           path: path
                                         };
                                         root.done = true;
                                       });
  }
  Timer {
    interval: 100
    running: root.done
    repeat: true
    onTriggered: {
      if (root.result.path && image.status !== Image.Ready && image.status !== Image.Error)
        return;
      stop();
      if (!image.grabToImage(result => {
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     name: "remote-red",
                                                     saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/remote-red.png")
                                                   }));
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         done: root.done,
                                                         result: root.result,
                                                         imageStatus: image.status
                                                       }));
        Qt.quit();
      })) {
        console.error("Malformed download grab rejected");
        Qt.exit(3);
      }
    }
  }
  Timer {
    interval: 20000
    running: true
    onTriggered: Qt.exit(3)
  }
}
