import QtQuick
import Quickshell

ShellRoot {
  id: controlRoot
  property var control: Qt.createQmlObject('import ReadyControl 1.0; ReadyControl {}', controlRoot)
  Timer {
    interval: 100
    running: true
    onTriggered: {
      console.log("READY_POLL_CONTROL " + JSON.stringify(controlRoot.control.run(Quickshell.env("READY_POLL_KIND") === "ppoll", Quickshell.env("READY_POLL_MODE") === "ready")));
      Qt.quit();
    }
  }
}
