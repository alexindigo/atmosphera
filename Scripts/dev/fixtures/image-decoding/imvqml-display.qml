import QtQuick
import Quickshell
import qs.Widgets

ShellRoot {
  FloatingWindow {
    id: window
    implicitWidth: 160
    implicitHeight: 100
    visible: true
    NImageBackdrop {
      id: picture
      anchors.fill: parent
      source: "data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='64'%20height='64'%3E%3Crect%20width='64'%20height='64'%20fill='red'/%3E%3C/svg%3E"
    }
    property int step: 0
    Timer {
      interval: 100
      running: true
      repeat: true
      onTriggered: {
        if (window.step === 0 && picture.imageState === "ready") {
          if (!picture.displayedSource || !picture.outputUrl) {
            Qt.exit(4);
            return;
          }
          window.step = 1;
          picture.source = "data:application/octet-stream;base64,YmFkIGRhdGE=";
        } else if (window.step === 1 && picture.imageState === "unavailable") {
          if (picture.displayedSource === picture.source || !picture.displayedSource || !picture.errorReason) {
            Qt.exit(5);
            return;
          }
          console.log("IMV_DISPLAY PASS", picture.errorReason);
          Qt.quit();
        }
      }
    }
  }
  Timer {
    interval: 9000
    running: true
    onTriggered: Qt.exit(6)
  }
}
