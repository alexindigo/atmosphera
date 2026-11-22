import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Actual AtmoAppIcon (XdgIcon theme lookup in the private XDG data root) and
// AtmoIcon (registered icon-set files). Pixels are grabbed from the consumers.
ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int pending: 0
  property bool registered: false
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  FileView {
    path: root.inputs + "/icon-set/icons.json"
    onLoaded: {
      IconRegistry.register("fixture:image-icons", JSON.parse(text()), root.inputs + "/icon-set");
      root.registered = true;
    }
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
      status: "status" in item ? item.status : null,
      failed: "failed" in item ? item.failed : null,
      reason: "errorReason" in item ? item.errorReason : "",
      source: "source" in item ? String(item.source) : "",
      width: item.width,
      height: item.height
    };
  }
  readonly property var appNames: [["webp", "fixture-webp-app", "fixture-none"], ["png", "fixture-png-app", "fixture-none"], ["svg", "fixture-svg-app", "fixture-none"], ["missing", "fixture-missing-app", "fixture-png-app"], ["corrupt", "fixture-corrupt-app", "fixture-svg-app"]]
  readonly property var glyphNames: ["webp", "png", "svg", "corrupt"]
  FloatingWindow {
    visible: true
    implicitWidth: 400
    implicitHeight: 200
    color: "transparent"
    Row {
      Repeater {
        id: apps
        model: root.appNames
        AtmoAppIcon {
          required property var modelData
          width: 64
          height: 64
          size: 64
          name: modelData[1]
          fallbackName: modelData[2]
        }
      }
    }
    Row {
      y: 80
      Repeater {
        id: glyphs
        model: root.registered ? root.glyphNames : []
        AtmoIcon {
          required property var modelData
          icon: "fixture-glyph-" + modelData
          pointSize: 40
          applyUiScale: false
          color: "#2341e1"
        }
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 40) {
        for (var i = 0; i < apps.count; ++i)
          root.grab(apps.itemAt(i), "app-" + root.appNames[i][0]);
        for (var j = 0; j < glyphs.count; ++j)
          root.grab(glyphs.itemAt(j), "glyph-" + root.glyphNames[j]);
      }
      if (root.tick >= 50 && !root.pending) {
        var result = {
          apps: {},
          glyphs: {},
          glyphCount: glyphs.count,
          warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
        };
        for (var a = 0; a < apps.count; ++a)
          result.apps[root.appNames[a][0]] = root.describe(apps.itemAt(a));
        for (var g = 0; g < glyphs.count; ++g)
          result.glyphs[root.glyphNames[g]] = root.describe(glyphs.itemAt(g));
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
