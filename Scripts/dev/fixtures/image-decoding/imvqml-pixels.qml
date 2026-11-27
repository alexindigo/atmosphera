pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Widgets

ShellRoot {
  FloatingWindow {
    id: window
    implicitWidth: 160
    implicitHeight: 80

    Rectangle {
      id: card
      width: 160
      height: 80
      color: "black"
      readonly property string svg: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="40" height="80" fill="red" fill-opacity="0.5"/><rect x="40" width="40" height="80" fill="red"/></svg>')
      NImage {
        id: rounded
        width: 80
        height: 80
        source: card.svg
        roundedRadius: 30
      }
      NImage {
        id: tinted
        anchors.left: rounded.right
        width: 80
        height: 80
        source: card.svg
        alphaMaskTint: Qt.rgba(0, 1, 0, 0.5)
      }
    }

    Timer {
      id: sample
      interval: 100
      repeat: true
      running: true
      onTriggered: {
        if (rounded.imageState !== "ready" || tinted.imageState !== "ready")
          return;
        stop();
        if (!card.grabToImage(result => {
          if (result.saveToFile(Quickshell.env("ATMO_PIXEL_FILE")))
            Qt.quit();
          else
            Qt.exit(4);
        }, Qt.size(160, 80)))
          Qt.exit(3);
      }
    }
  }
  Timer {
    interval: 12000
    running: true
    onTriggered: Qt.exit(5)
  }
}
