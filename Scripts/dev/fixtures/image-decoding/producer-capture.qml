import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "./Helpers/ImageBytes.js" as ImageBytes
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property bool started: false
  property bool producerDone: false
  property int pending: 0
  property int grabs: 0
  property var captured: []
  property var results: []
  property var late: []
  property var legacyFiles: []
  property var byteControls: []
  property var missing: null
  property var empty: null
  property var badProvider: null
  property var cancelCallbacks: []
  property var cancelled: null
  property int producerExit: -1
  property string producerErrors: ""

  Component {
    id: probeFactory
    Image {
      asynchronous: false
      cache: false
    }
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
          grabToImage(result => {
            console.log("IMAGE_GRAB|" + JSON.stringify({
                                                         name: "retained-" + rowIndex,
                                                         saved: result.saveToFile(root.output + "/retained-" + rowIndex + ".png")
                                                       }));
            active = false;
            --root.grabs;
          });
        }
      }
    }
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 640
    implicitHeight: 128
    color: "transparent"
    Image {
      id: raw
      width: 64
      height: 64
      source: root.inputs + "/Still.webp"
    }
    Item {
      id: presentations
      y: 64
      width: 640
      height: 64
    }
  }

  function capture(notification) {
    if (notification.image.startsWith("file:")) {
      ImageCacheService.getNotificationIcon(notification.image, notification.appName, notification.summary, function (path, success) {
        root.legacyFiles.push({
                                path: path,
                                success: success
                              });
      });
    }
    const snapshot = ImageCacheService.captureSource(notification.image);
    root.captured.push({
                         source: snapshot.source || "",
                         original: notification.image,
                         snapshot: snapshot,
                         id: notification.id
                       });
  }
  NotificationServer {
    imageSupported: true
    onNotification: notification => {
      notification.tracked = true;
      notification.imageChanged.connect(function () {
        root.capture(notification);
      });
      root.capture(notification);
    }
  }
  Process {
    id: producer
    command: ["python3", Quickshell.env("IMAGE_PRODUCER"), root.inputs]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: code => {
      root.producerExit = code;
      root.producerErrors = stderr.text;
      root.producerDone = true;
      for (const row of root.legacyFiles) {
        const node = probeFactory.createObject(presentations, {
                                                 source: row.path
                                               });
        row.statusAfterLoss = node.status;
        node.destroy();
      }
      // No persistence/decode work starts until the real producer has closed
      // all notifications and unlinked its files.
      for (let i = 0; i < root.captured.length; i++) {
        const row = root.captured[i];
        if (row.original.startsWith("image://")) {
          const node = probeFactory.createObject(presentations, {
                                                   source: row.original + "/uncached"
                                                 });
          root.late.push({
                           index: i,
                           status: node.status
                         });
          node.destroy();
        }
        ++root.pending;
        ImageCacheService.retainImage(row.source, root.output + "/retained", 64, 64, function (path, success, detail) {
          root.results.push({
                              index: i,
                              path: path,
                              success: success,
                              detail: detail
                            });
          if (success)
            resultFactory.createObject(presentations, {
                                         source: path,
                                         rowIndex: i,
                                         x: i * 64
                                       });
          --root.pending;
        });
      }
      root.cancelled = ImageCacheService.retainImage(root.captured[0].source, root.output + "/cancelled", 64, 64, function (path, success) {
        root.cancelCallbacks.push({
                                    path: path,
                                    success: success
                                  });
      });
      root.cancelled.cancel();
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (!root.started && ImageCacheService.admissionReady && raw.status !== Image.Loading) {
        root.started = true;
        for (let length of [0, 1, 2, 3, 255, 256, 257]) {
          const bytes = new Uint8Array(length);
          for (let i = 0; i < length; i++)
            bytes[i] = i % 256;
          root.byteControls.push({
                                   length: length,
                                   url: ImageBytes.dataUrl(bytes.buffer)
                                 });
        }
        root.missing = ImageCacheService.captureSource(root.inputs + "/Missing.webp");
        root.empty = ImageCacheService.captureSource("");
        root.badProvider = ImageCacheService.captureSource("image://qsimage/unknown");
        root.captured.push({
                             source: Quickshell.env("IMAGE_DATA"),
                             original: "inline-data",
                             snapshot: {
                               captureKind: "bytes"
                             },
                             id: -1
                           });
        producer.running = true;
      }
      if (root.producerDone && root.pending === 0 && root.grabs === 0 && root.results.length === root.captured.length && presentations.children.length === root.results.filter(r => r.success).length && presentations.children.every(item => item.grabbed && !item.active) && ImageCacheService.sourceInterestCount === 0 && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         raw: raw.status,
                                                         captured: root.captured,
                                                         results: root.results,
                                                         late: root.late,
                                                         legacyFiles: root.legacyFiles,
                                                         bytes: root.byteControls,
                                                         missing: root.missing,
                                                         empty: root.empty,
                                                         badProvider: root.badProvider,
                                                         cancelled: root.cancelCallbacks,
                                                         producerExit: root.producerExit,
                                                         producerErrors: root.producerErrors,
                                                         interests: ImageCacheService.sourceInterestCount,
                                                         worker: ImageCacheService.sourceWorkerRunning
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
