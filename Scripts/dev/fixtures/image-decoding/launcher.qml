import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Launcher
import qs.Services.UI
import qs.Widgets

// Actual launcher list and grid delegates with a fixture image provider:
// decodable art, art that fails, and a row without art (ordinary icon).
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
  QtObject {
    id: provider
    property int imageRevision: 0
    signal itemImageChanged(var identity)
    function getImageUrl(row) {
      return row.url;
    }
  }
  QtObject {
    id: launcherState
    property int selectedIndex: -1
    property real entryHeight: 64
    property bool isCompactDensity: false
    property real badgeSize: 48
    property bool selectionAnimated: false
    property var currentProvider: provider
    property bool providerHasDisplayString: false
    function activate() {
    }
  }
  readonly property var kinds: ["art", "failed", "noart"]
  readonly property var rows: [
    {
      key: "art",
      row: {
        name: "Art",
        description: "",
        icon: "fixture-png-app",
        isImage: true,
        isTablerIcon: false,
        provider: provider,
        url: root.inputs + "/Misleading.png"
      }
    },
    {
      key: "failed",
      row: {
        name: "Failed",
        description: "",
        icon: "fixture-png-app",
        isImage: true,
        isTablerIcon: false,
        provider: provider,
        url: root.inputs + "/Corrupt.webp"
      }
    },
    {
      key: "noart",
      row: {
        name: "No art",
        description: "",
        icon: "fixture-png-app",
        isImage: true,
        isTablerIcon: false,
        provider: provider,
        url: ""
      }
    }
  ]
  function reportGrab(name: string, error: string): void {
    console.log("IMAGE_GRAB|" + JSON.stringify({
                                                 name: name,
                                                 saved: !error,
                                                 error: error
                                               }));
  }
  function grab(item: Item, name: string): void {
    if (!item) {
      reportGrab(name, "delegate-absent");
      return;
    }
    if (item.grabToImage(result => {
      root.reportGrab(name, result.saveToFile(root.output + "/" + name + ".png") ? "" : "save-failed");
      --root.pending;
    }))
      ++pending;
    else
      reportGrab(name, "grab-rejected");
  }
  FloatingWindow {
    visible: true
    implicitWidth: 640
    implicitHeight: 360
    color: "transparent"
    ListView {
      id: list
      width: 320
      height: 240
      model: root.rows
      interactive: false
      delegate: LauncherListDelegate {
        launcher: launcherState
      }
    }
    GridView {
      id: grid
      x: 330
      width: 300
      height: 120
      cellWidth: 100
      cellHeight: 100
      model: root.rows
      interactive: false
      delegate: LauncherGridDelegate {
        launcher: launcherState
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
        for (var i = 0; i < root.kinds.length; ++i) {
          root.grab(list.itemAtIndex(i), "list-" + root.kinds[i]);
          root.grab(grid.itemAtIndex(i), "grid-" + root.kinds[i]);
        }
      }
      if (root.tick >= 50 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         listCount: list.count,
                                                         gridCount: grid.count,
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
