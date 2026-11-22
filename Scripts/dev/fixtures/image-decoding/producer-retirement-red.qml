import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services.UI

// Baseline-only witness. These exact adapter calls must not remain required
// by the positive producer-capture contract after the competing path retires.
ShellRoot {
  id: root
  property var legacyFiles: []
  property bool started: false
  property bool finished: false
  property int producerExit: -1
  property string producerErrors: ""
  Component {
    id: probeFactory
    Image {
      asynchronous: false
      cache: false
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 64
    implicitHeight: 64
    Rectangle {
      id: control
      anchors.fill: parent
      color: "red"
    }
  }
  NotificationServer {
    imageSupported: true
    onNotification: notification => {
      notification.tracked = true;
      if (notification.image.startsWith("file:")) {
        ImageCacheService.getNotificationIcon(notification.image, notification.appName, notification.summary, function (path, success) {
          root.legacyFiles.push({
                                  path: path,
                                  success: success
                                });
        });
      }
    }
  }
  Process {
    id: producer
    command: ["python3", Quickshell.env("IMAGE_PRODUCER"), Quickshell.env("IMAGE_FIXTURES")]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: code => {
      root.producerExit = code;
      root.producerErrors = stderr.text;
      for (const row of root.legacyFiles) {
        const node = probeFactory.createObject(control, {
                                                 source: row.path
                                               });
        row.statusAfterLoss = node.status;
        node.destroy();
      }
      control.grabToImage(result => {
        console.log("IMAGE_GRAB|" + JSON.stringify({
                                                     name: "control",
                                                     saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/control.png")
                                                   }));
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         legacyFiles: root.legacyFiles,
                                                         producerExit: root.producerExit,
                                                         producerErrors: root.producerErrors
                                                       }));
        Qt.quit();
      });
      root.finished = true;
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (!root.started && ImageCacheService.admissionReady) {
        root.started = true;
        producer.running = true;
      }
    }
  }
  Timer {
    interval: 23000
    running: true
    onTriggered: Qt.exit(2)
  }
}
