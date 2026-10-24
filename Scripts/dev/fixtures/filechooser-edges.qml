import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.FileChooser

ShellRoot {
  id: root
  property int size: 96
  property string kind: "folder"
  property string saved: ""
  PanelWindow {
    implicitWidth: 240
    implicitHeight: 240
    color: "transparent"
    Item {
      id: tile
      x: 16; y: 16
      width: root.size; height: root.size
      FileIcon {
        anchors.fill: parent
        compact: root.size === 20
        descriptor: ({type: root.kind, group: root.kind === "folder" ? "folder" : "text", folder: "ordinary", hidden: false})
      }
    }
  }
  IpcHandler {
    target: "filechooserEdges"
    function state(): string { return JSON.stringify({size: root.size, kind: root.kind, saved: root.saved}); }
    function configure(size: int, kind: string): void { root.size = size; root.kind = kind; root.saved = ""; }
    function capture(file: string): void {
      tile.grabToImage(function(result) { if (result.saveToFile(file)) root.saved = file; });
    }
    function quit(): void { Qt.quit(); }
  }
}
