import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Widgets
import qs.Modules.FileChooser
import qs.Services.UI
import qs.Widgets

// Shared small-image presentation (NImageIcon) and actual shell roots that
// use it: the bar ControlCenter custom icon and the chooser's app options row.
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
  readonly property var iconCases: [["webp", root.inputs + "/Misleading.png"], ["svg", root.inputs + "/Still.svg"], ["corrupt", root.inputs + "/Corrupt.webp"], ["provider", "image://icon/fixture-missing-provider-icon"], ["unprovided", "image://fixture-no-such-provider/image"]]
  FloatingWindow {
    visible: true
    implicitWidth: 560
    implicitHeight: 240
    color: "transparent"
    Row {
      Repeater {
        id: icons
        model: root.iconCases
        NImageIcon {
          required property var modelData
          width: 64
          height: 64
          source: modelData[1]
        }
      }
    }
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
        for (var i = 0; i < icons.count; ++i)
          root.grab(icons.itemAt(i), "icon-" + root.iconCases[i][0]);
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
        for (var j = 0; j < icons.count; ++j)
          result.icons[root.iconCases[j][0]] = root.describe(icons.itemAt(j));
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
