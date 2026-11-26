import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property bool historyOpened: false
  property bool started: false
  property bool producerDone: false
  property int producerExit: -1
  property string producerErrors: ""
  property var admitted: []
  property var results: []
  property var cancelCallbacks: []
  property var failures: []
  property int grabs: 0

  Component.onCompleted: {
    ImageCacheService.openNotificationHistory(Quickshell.env("IMAGE_FIXTURES") + "/adapter-history.json", ok => {
      if (ok)
        root.historyOpened = true;
      else
        root.fail("Could not open the adapter's private notification history");
    });
  }

  function fail(message) {
    console.error("NOTIFICATION_ADAPTER|" + message);
    Qt.exit(2);
  }

  Component {
    id: resultFactory
    NImage {
      width: 64
      height: 64
      animationIntent: "still"
      property int rowIndex
      property bool grabbed: false
      onStatusChanged: {
        if (status === Image.Ready && !grabbed) {
          grabbed = true;
          ++root.grabs;
          if (!grabToImage(result => {
            console.log("IMAGE_GRAB|" + JSON.stringify({
                                                         name: "adapter-" + rowIndex,
                                                         saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/adapter-" + rowIndex + ".png")
                                                       }));
            active = false;
            --root.grabs;
          })) {
            --root.grabs;
            root.fail("Could not start grab for row " + rowIndex);
          }
        }
      }
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 640
    implicitHeight: 128
    Item {
      id: presentations
      y: 64
      width: 640
      height: 64
    }
  }
  function admit(source, notificationId) {
    const index = root.admitted.length;
    root.admitted.push({
                         original: source,
                         id: notificationId
                       });
    ImageCacheService.getNotificationIcon(source, function (path, success, detail) {
      root.results.push({
                          index: index,
                          path: path,
                          success: success,
                          detail: detail
                        });
      if (!success) {
        root.fail("Admission failed for row " + index + ": " + JSON.stringify(detail));
        return;
      }
      // Take the consumer's hold before the adapter releases its pending
      // ticket, just as NotificationService does when publishing an entry.
      ImageCacheService.updateNotificationHolders(root.results.map(row => row.path));
      resultFactory.createObject(presentations, {
                                   source: path,
                                   rowIndex: index,
                                   x: index * 64
                                 });
    });
  }
  NotificationServer {
    imageSupported: true
    onNotification: notification => {
      notification.tracked = true;
      notification.imageChanged.connect(function () {
        root.admit(notification.image, notification.id);
      });
      root.admit(notification.image, notification.id);
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
      root.producerDone = true;
      if (code !== 0)
        root.fail("Producer exited " + code + ": " + root.producerErrors);
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (!root.started && root.historyOpened) {
        root.started = true;
        for (const source of ["", Quickshell.env("IMAGE_FIXTURES") + "/Missing.webp", "image://qsimage/unknown", Quickshell.env("IMAGE_FIXTURES") + "/Corrupt.webp"])
          ImageCacheService.getNotificationIcon(source, function (path, success, detail) {
            root.failures.push({
                                 path: path,
                                 success: success,
                                 detail: detail
                               });
          });
        const cancelled = ImageCacheService.getNotificationIcon(Quickshell.env("IMAGE_DATA"), function (path, success) {
          root.cancelCallbacks.push({
                                      path: path,
                                      success: success
                                    });
        });
        cancelled.cancel();
        root.admit(Quickshell.env("IMAGE_DATA"), -1);
        producer.running = true;
      }
      if (root.producerDone && root.results.length === root.admitted.length && root.failures.length === 4 && root.grabs === 0 && presentations.children.length === 9 && presentations.children.every(item => item.grabbed && !item.active)) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         admitted: root.admitted,
                                                         results: root.results,
                                                         failures: root.failures,
                                                         cancelled: root.cancelCallbacks,
                                                         producerExit: root.producerExit,
                                                         producerErrors: root.producerErrors
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 23000
    running: true
    onTriggered: Qt.exit(2)
  }
}
