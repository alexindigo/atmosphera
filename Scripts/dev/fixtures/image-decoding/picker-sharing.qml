import QtQuick
import Quickshell
import qs.Widgets

ShellRoot {
  id: root
  readonly property string path: Quickshell.env("IMAGE_FIXTURES") + "/Shared.mp4"
  property int phase: 0

  FloatingWindow {
    visible: true
    implicitWidth: 180
    implicitHeight: 160
    Row {
      Repeater {
        id: previews
        model: 2
        NImage {
          required property int index
          width: 90
          height: 160
          active: root.phase < (index === 0 ? 1 : 3)
          source: active ? root.path : ""
          sourceSize: Qt.size(90, 160)
        }
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      const first = previews.itemAt(0);
      const second = previews.itemAt(1);
      if (root.phase === 0 && first.imageState === "ready" && second.imageState === "ready") {
        root.phase = 1;
      } else if (root.phase === 1 && first.imageState === "idle" && second.imageState === "ready") {
        root.phase = 2;
        if (!second.grabToImage(result => {
          const saved = result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/survivor.png");
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       saved: saved
                                                     }));
          root.phase = 3;
        }))
          Qt.exit(2);
      } else if (root.phase === 3 && first.imageState === "idle" && second.imageState === "idle") {
        console.log('IMAGE_BASELINE|{"bothReady":true,"survived":true,"bothRetired":true}');
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 18000
    running: true
    onTriggered: Qt.exit(3)
  }
}
