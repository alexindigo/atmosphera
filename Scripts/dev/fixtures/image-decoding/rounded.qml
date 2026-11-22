import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int pending: 0
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  function grab(item, name) {
    ++pending;
    item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    });
  }
  function describe(item) {
    return {
      status: item.status,
      fallback: item.showFallback,
      reason: "errorReason" in item ? item.errorReason : "",
      result: "imageResult" in item ? item.imageResult : {}
    };
  }
  FloatingWindow {
    visible: true
    implicitWidth: 600
    implicitHeight: 320
    color: "transparent"
    Row {
      NImageRounded {
        id: still
        width: 128
        height: 128
        radius: 24
        imagePath: root.inputs + "/Still.webp"
      }
      NImageRounded {
        id: motion
        width: 128
        height: 128
        radius: 24
        imagePath: root.inputs + "/Motion.webp"
      }
      NImageRounded {
        id: data
        width: 128
        height: 128
        radius: width / 2
        imagePath: Quickshell.env("IMAGE_DATA")
      }
      NImageRounded {
        id: failed
        width: 128
        height: 128
        radius: 24
        imagePath: root.inputs + "/Corrupt.webp"
        fallbackIcon: "person"
      }
    }
    Row {
      y: 160
      NImageRounded {
        id: fit
        width: 128
        height: 128
        radius: 24
        imagePath: root.inputs + "/geometry.png"
        imageFillMode: Image.PreserveAspectFit
      }
      NImageRounded {
        id: crop
        width: 128
        height: 128
        radius: 24
        imagePath: root.inputs + "/geometry.png"
        imageFillMode: Image.PreserveAspectCrop
      }
      NImageRounded {
        id: stretch
        width: 128
        height: 128
        radius: 24
        imagePath: root.inputs + "/geometry.png"
        imageFillMode: Image.Stretch
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick >= 15 && root.tick <= 40)
        root.grab(motion, "motion-" + root.tick);
      if (root.tick === 40) {
        root.grab(still, "still");
        root.grab(data, "data");
        root.grab(failed, "failure");
        root.grab(fit, "fit");
        root.grab(crop, "crop");
        root.grab(stretch, "stretch");
      }
      if (root.tick >= 50 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         still: root.describe(still),
                                                         motion: root.describe(motion),
                                                         data: root.describe(data),
                                                         failure: root.describe(failed),
                                                         reduced: Settings.data.general.animationDisabled,
                                                         warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
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
