import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

// Red control: a baseline NText in its rich and Markdown modes with images.
ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int pending: 0
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
  FloatingWindow {
    visible: true
    implicitWidth: 420
    implicitHeight: 200
    color: "white"
    Column {
      NText {
        id: rich
        width: 400
        color: "black"
        richTextEnabled: true
        text: "rich <img src='file://" + root.inputs + "/Misleading.png' width='32' height='24'> tail"
      }
      NText {
        id: markdown
        width: 400
        color: "black"
        markdownTextEnabled: true
        text: "md <img src=\"file://" + root.inputs + "/frame-0.png\" width=\"32\" height=\"24\"> tail"
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 30) {
        root.grab(rich, "rich");
        root.grab(markdown, "markdown");
      }
      if (root.tick >= 40 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         markdownText: markdown.text
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
