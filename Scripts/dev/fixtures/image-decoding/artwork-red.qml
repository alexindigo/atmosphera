import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Widgets
import qs.Modules.FileChooser
import qs.Services.UI
import qs.Widgets

// Red control: the actual bar ControlCenter custom icon and the chooser's app
// options row of a baseline tree, without the shared presentation widget.
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
      state: item.imageState,
      failed: item.failed,
      code: item.errorCode,
      reason: item.errorReason,
      width: item.width,
      height: item.height
    };
  }
  readonly property var iconCases: [["webp", root.inputs + "/Misleading.png"], ["svg", root.inputs + "/Still.svg"], ["corrupt", root.inputs + "/Corrupt.webp"], ["provider", "image://icon/fixture-missing-provider-icon"]]
  FloatingWindow {
    visible: true
    implicitWidth: 480
    implicitHeight: 240
    color: "transparent"
    ControlCenter {
      id: controlCenter
      y: 80
      widgetSettings: ({
                         customIconPath: root.inputs + "/Misleading.png",
                         useDistroLogo: false,
                         enableColorization: false,
                         icon: "",
                         colorizeSystemIcon: "none"
                       })
    }
    FileAppOptions {
      id: appOptions
      y: 160
      width: 300
      request: ({
                  appIcon: "fixture-webp-app",
                  appOptionsLabel: "Fixture options",
                  choices: []
                })
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 40) {
        root.grab(controlCenter, "control-center");
        root.grab(appOptions, "app-options");
      }
      if (root.tick >= 50 && !root.pending) {
        var result = {
          icons: {},
          controlCenter: {
            width: controlCenter.width,
            height: controlCenter.height,
            customIconPath: controlCenter.customIconPath
          },
          appOptions: {
            width: appOptions.width,
            height: appOptions.height
          },
          warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
        };
        console.log("IMAGE_BASELINE|" + JSON.stringify(result));
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
