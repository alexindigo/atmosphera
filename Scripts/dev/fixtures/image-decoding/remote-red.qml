import QtQuick
import Quickshell
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property var result: ({})
  property bool done: false
  FloatingWindow {
    visible: true
    implicitWidth: 96
    implicitHeight: 64
    NImage {
      id: image
      anchors.fill: parent
      source: root.result.path || ""
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
    interval: 3000
    running: true
    onTriggered: {
      image.grabToImage(result => {
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/remote-red.png")
                                                   }));
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         done: root.done,
                                                         result: root.result,
                                                         imageStatus: image.status
                                                       }));
        Qt.quit();
      });
    }
  }
}
