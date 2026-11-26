import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property bool finishing: false
  Component.onCompleted: ImageCacheService.init()
  FloatingWindow {
    visible: true
    implicitWidth: 96
    implicitHeight: 96
    NImage {
      id: seed
      width: 96
      height: 96
      source: Quickshell.env("IMAGE_FIXTURES") + "/frame-1.png"
    }
  }
  Process {
    id: scan
    command: ["find", Settings.cacheDir + "images/decoded", "-type", "f", "-name", "*.imvqoi", "-printf", "%f\n"]
    stdout: StdioCollector {
      id: inventory
    }
    onExited: code => {
      if (code === 0 && inventory.text.trim() && !root.finishing) {
        root.finishing = true;
        const entry = inventory.text.trim();
        if (!seed.grabToImage(result => {
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/seed.png")
                                                     }));
          console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                           entry: entry
                                                         }));
          Qt.quit();
        }))
          Qt.exit(3);
      }
    }
  }
  Timer {
    interval: 100
    repeat: true
    running: seed.status === Image.Ready
    onTriggered: if (!scan.running)
                   scan.running = true
  }
  Timer {
    interval: 10000
    running: true
    onTriggered: Qt.exit(3)
  }
}
