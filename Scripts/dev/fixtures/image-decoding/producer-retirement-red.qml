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
  readonly property bool holdReplies: Quickshell.env("IMAGE_LEGACY_HOLD_CALLBACKS") === "1"
  property var heldReplies: []
  property int pendingCallbacks: 0
  property int tick: 0
  property int exitedAt: -1
  Component.onCompleted: {
    if (!ImageCacheService.initialized)
      ImageCacheService.init();
  }
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
        ++root.pendingCallbacks;
        ImageCacheService.getNotificationIcon(notification.image, notification.appName, notification.summary, function (path, success) {
          var row = {
            path: path,
            success: success
          };
          if (root.holdReplies) {
            root.heldReplies.push(row);
          } else {
            root.legacyFiles.push(row);
            --root.pendingCallbacks;
          }
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
      root.exitedAt = root.tick;
    }
  }
  function finish() {
    root.finished = true;
    for (const row of root.legacyFiles) {
      const node = probeFactory.createObject(control, {
                                               source: row.path
                                             });
      row.statusAfterLoss = node.status;
      node.destroy();
    }
    var accepted = control.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: "control",
                                                   saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/control.png")
                                                 }));
      console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                       legacyFiles: root.legacyFiles,
                                                       pendingCallbacks: root.pendingCallbacks,
                                                       producerExit: root.producerExit,
                                                       producerErrors: root.producerErrors
                                                     }));
      Qt.quit();
    });
    if (!accepted)
      Qt.exit(4);
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      // Hold genuine adapter replies past producer exit to exercise callback
      // settlement independently of this machine's converter scheduling.
      if (root.producerExit >= 0 && root.tick > root.exitedAt + 3) {
        while (root.heldReplies.length) {
          root.legacyFiles.push(root.heldReplies.shift());
          --root.pendingCallbacks;
        }
      }
      if (!root.started && ImageCacheService.initialized) {
        root.started = true;
        producer.running = true;
      }
      if (root.started && root.producerExit >= 0 && !root.pendingCallbacks && !root.finished)
        root.finish();
    }
  }
  Timer {
    interval: 23000
    running: true
    onTriggered: Qt.exit(2)
  }
}
