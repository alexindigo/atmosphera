pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property var cases: [
    {
      name: "thumbnail",
      file: "Motion.webp",
      side: 64
    },
    {
      name: "large",
      file: "Motion.webp",
      side: 192
    },
    {
      name: "avatar",
      file: "Still.webp",
      side: 128
    },
    {
      name: "misleading",
      file: "Misleading.png",
      side: 128
    },
    {
      name: "literal",
      file: "bracket[0]: image.webp",
      side: 128
    },
    {
      name: "corrupt",
      file: "Corrupt.webp",
      side: 64
    },
    {
      name: "missing",
      file: "Missing.webp",
      side: 64
    }
  ]
  property int phase: 0
  property var presented: []
  property int grabs: 0
  property int cancelledDeliveries: 0

  Component.onCompleted: {
    ImageCacheService.init();
    cancelled.source = root.inputs + "/frame-2.png";
    cancelled.active = false;
  }

  FloatingWindow {
    visible: true
    implicitWidth: 800
    implicitHeight: 192
    color: "transparent"
    Row {
      Repeater {
        id: images
        model: root.cases
        NImage {
          required property var modelData
          width: modelData.side
          height: width
          source: root.inputs + "/" + modelData.file
          animationIntent: "still"
          roundedRadius: modelData.name === "avatar" ? width / 2 : 0
        }
      }
    }
    NImage {
      id: cancelled
      width: 64
      height: 64
      onStatusChanged: {
        if (status === Image.Ready || status === Image.Error)
          ++root.cancelledDeliveries;
      }
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      const items = Array.from({
                                 length: images.count
                               }, (_, i) => images.itemAt(i) as NImage);
      if (root.phase === 0 && items.length === root.cases.length && items.every(item => item.status === Image.Ready || item.status === Image.Error)) {
        root.phase = 1;
        root.presented = items.map((item, i) => ({
          name: root.cases[i].name,
          status: item.status,
          url: item.outputUrl,
          reason: item.errorReason,
          frames: item.frameCount
        }));
        for (let i = 0; i < items.length; ++i) {
          const item = items[i];
          const name = root.cases[i].name;
          if (item.status !== Image.Ready)
            continue;
          ++root.grabs;
          if (!item.grabToImage(result => {
            console.log("IMAGE_GRAB|" + JSON.stringify({
                                                         name: name,
                                                         saved: result.saveToFile(root.output + "/" + name + ".png")
                                                       }));
            --root.grabs;
          }))
            Qt.exit(3);
        }
      } else if (root.phase === 1 && !root.grabs) {
        root.phase = 2;
        items.forEach(item => item.active = false);
      } else if (root.phase === 2 && items.every(item => item.status === Image.Null && !item.outputUrl)) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         presented: root.presented,
                                                         retired: items.length,
                                                         cancelledStatus: cancelled.status,
                                                         cancelledDeliveries: root.cancelledDeliveries
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
