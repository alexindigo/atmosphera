import QtQuick
import Quickshell
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property var names: ["frame-0.png", "Still.webp", "Still.jpg", "Still.svg", "Still.tiff", "Still.avif", "Still.heic", "Still.jxl", "Misleading.png", "Oriented.jpg", "Motion.webp", "Motion.gif", "Corrupt.webp", "Still.webp"]
  property int index: 0
  property int tick: 0
  property bool pending: false
  property var rows: []

  FloatingWindow {
    implicitWidth: 192
    implicitHeight: 128
    visible: true
    NImage {
      id: image
      anchors.fill: parent
      source: root.inputs + "/" + root.names[root.index]
      sourceSize: Qt.size(192, 128)
      fillMode: Image.PreserveAspectFit
      animationIntent: "preserve"
      playing: true
    }
  }
  Timer {
    interval: 90
    repeat: true
    running: true
    onTriggered: {
      const moving = root.names[root.index].startsWith("Motion.");
      if (root.pending || (image.imageState !== "ready" && image.imageState !== "unavailable"))
        return;
      root.pending = true;
      const name = "format-" + root.index + "-" + root.tick;
      const row = {
        name: root.names[root.index],
        state: image.imageState,
        code: image.errorCode,
        width: image.decodedSize.width,
        height: image.decodedSize.height,
        frames: image.frameCount,
        capture: name
      };
      if (!image.grabToImage(result => {
        root.rows.push(row);
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     name: name,
                                                     saved: result.saveToFile(root.output + "/" + name + ".png")
                                                   }));
        if (!moving || ++root.tick === 18) {
          root.tick = 0;
          if (root.index + 1 === root.names.length) {
            console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                             images: root.rows
                                                           }));
            Qt.quit();
            return;
          }
          ++root.index;
        }
        root.pending = false;
      }))
        Qt.exit(2);
    }
  }
  Timer {
    interval: 18000
    running: true
    onTriggered: Qt.exit(3)
  }
}
