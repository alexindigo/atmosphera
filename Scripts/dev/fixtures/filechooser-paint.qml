import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.FileChooser

ShellRoot {
  id: root
  property var states: []
  property var pending: ({})
  property int size: 96
  property string background: "black"
  property bool coldActive: false
  property int warmCreations: 0
  property int coldCreations: 0
  property string phase: "idle"
  property string completed: ""
  property bool seedRendered: false
  property bool saved: false

  function apply(data) {
    AtmoColor.skipTransition = true;
    for (var key of Object.keys(data.colors)) {
      if (key.startsWith("m"))
        AtmoColor[key] = data.colors[key];
    }
    background = data.colors.mSurface;
    states = data.descriptors;
  }

  PanelWindow {
    implicitWidth: sheet.width + 32
    implicitHeight: sheet.height + 32
    color: root.background
    Item {
      id: sheet
      x: 16
      y: 16
      width: 6 * (2 * root.size + 8)
      height: 6 * (root.size + 8)
      Repeater {
        model: root.states.length
        Item {
          id: cell
          required property int index
          x: (index % 6) * (2 * root.size + 8)
          y: Math.floor(index / 6) * (root.size + 8)
          width: 2 * root.size + 8
          height: root.size + 8
          Rectangle {
            width: root.size
            height: root.size
            color: root.background
            FileIcon {
              anchors.fill: parent
              compact: root.size === 20
              descriptor: root.states[cell.index]
              Component.onCompleted: root.warmCreations++
            }
          }
          Rectangle {
            x: root.size + 8
            width: root.size
            height: root.size
            color: root.background
            Loader {
              anchors.fill: parent
              active: root.coldActive
              sourceComponent: FileIcon {
                anchors.fill: parent
                compact: root.size === 20
                descriptor: root.states[cell.index]
              }
              onLoaded: root.coldCreations++
            }
          }
        }
      }
    }
  }

  Timer {
    id: seedFrame
    interval: 40
    onTriggered: {
      // Complete an actual seed render before changing properties. A binding
      // assignment alone does not prove that the old fill node was removed.
      sheet.grabToImage(function (result) {
        root.seedRendered = result.saveToFile(root.pending.seedFile);
        root.apply(root.pending.target);
        root.phase = "target";
        root.coldActive = true;
        targetFrame.start();
      });
    }
  }
  Timer {
    id: targetFrame
    interval: 40
    onTriggered: {
      sheet.grabToImage(function (result) {
        root.saved = result.saveToFile(root.pending.file);
        root.completed = root.pending.tag;
        root.phase = "idle";
      });
    }
  }

  IpcHandler {
    target: "filechooserPaint"
    function state(): string {
      return JSON.stringify({
                              ready: Settings.isLoaded,
                              phase: root.phase,
                              completed: root.completed,
                              seedRendered: root.seedRendered,
                              saved: root.saved,
                              count: root.states.length,
                              warmCreations: root.warmCreations,
                              coldCreations: root.coldCreations
                            });
    }
    function exercise(text: string): void {
      if (root.phase !== "idle")
        throw new Error("paint comparison already active");
      var data = JSON.parse(text);
      root.pending = data;
      root.coldActive = false;
      root.size = data.size;
      root.seedRendered = false;
      root.saved = false;
      root.phase = "seed";
      root.apply(data.seed);
      seedFrame.start();
    }
    function quit(): void {
      Qt.quit();
    }
  }
}
