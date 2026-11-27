import ImvQml
import QtQuick
import Quickshell
import "ImageBytes.js" as ImageBytes

ShellRoot {
  ImvImageJob {
    id: sampler
    property int ticket: 0
    Component.onCompleted: {
      ticket = sample(Quickshell.env("ATMO_SAMPLE_SOURCE"), 112, 112, 0.1);
      if (ticket <= 0)
        Qt.exit(1);
    }
    onFinished: (id, result) => {
      if (id !== ticket)
        return;
      if (result.code || !result.rgba) {
        console.error("Sample failed:", result.stage, result.code);
        Qt.exit(2);
        return;
      }
      console.log("ATMO_RGBA|" + JSON.stringify({
                                                  width: result.width,
                                                  height: result.height,
                                                  rgba: ImageBytes.base64(result.rgba)
                                                }));
      Qt.quit();
    }
  }
  Timer {
    running: true
    interval: 10000
    onTriggered: Qt.exit(3)
  }
}
