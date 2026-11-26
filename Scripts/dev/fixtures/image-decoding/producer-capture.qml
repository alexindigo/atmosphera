pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "./Helpers/ImageBytes.js" as ImageBytes
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property bool started: false
  property bool storeReady: false
  property bool producerDone: false
  property bool presented: false
  property int pending: 0
  property int grabs: 0
  property var captured: []
  property var results: []
  property var late: []
  property var byteControls: []
  property var refusals: []
  property var cancelCallbacks: []
  property int producerExit: -1
  property string producerErrors: ""

  Component.onCompleted: ImageCacheService.openNotificationHistory(root.inputs + "/capture-history.json", ok => {
    if (!ok)
      Qt.exit(4);
    root.storeReady = ok;
  })

  Component {
    id: probeFactory
    NImage {
      width: 1
      height: 1
      required property int rowIndex
      onImageStateChanged: {
        if (imageState !== "unavailable" && imageState !== "ready")
          return;
        root.late.push({
                         index: rowIndex,
                         state: imageState,
                         code: errorCode
                       });
        destroy();
      }
    }
  }
  Component {
    id: resultFactory
    NImage {
      width: 64
      height: 64
      animationIntent: "still"
      required property int rowIndex
      property bool grabbed: false
      onStatusChanged: {
        if (status === Image.Ready && !grabbed) {
          grabbed = true;
          if (grabToImage(result => {
            console.log("IMAGE_GRAB|" + JSON.stringify({
                                                         name: "retained-" + rowIndex,
                                                         saved: result.saveToFile(root.output + "/retained-" + rowIndex + ".png")
                                                       }));
            active = false;
            --root.grabs;
          })) {
            ++root.grabs;
          } else {
            console.error("Retained image grab rejected: retained-" + rowIndex);
            Qt.exit(3);
          }
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

  function capture(source, id) {
    const index = captured.length;
    captured.push({
                    original: source,
                    id: id
                  });
    ++pending;
    // This call must take ownership before the notification event returns.
    // No consumer renders until the producer has unlinked/closed everything.
    ImageCacheService.retainImage(source, output + "/retained", (path, success, detail) => {
      root.results.push({
                          index: index,
                          path: path,
                          success: success,
                          detail: detail
                        });
      --root.pending;
    });
  }
  NotificationServer {
    imageSupported: true
    onNotification: notification => {
      notification.tracked = true;
      notification.imageChanged.connect(function () {
        root.capture(notification.image, notification.id);
      });
      root.capture(notification.image, notification.id);
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
      for (let i = 0; i < root.captured.length; i++) {
        const row = root.captured[i];
        if (row.original.startsWith("image://"))
          probeFactory.createObject(window.contentItem, {
                                      source: row.original,
                                      rowIndex: i
                                    });
      }
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (!root.started && root.storeReady && raw.status !== Image.Loading) {
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
        for (const source of [root.inputs + "/Missing.webp", "", "image://qsimage/unknown"]) {
          ImageCacheService.retainImage(source, root.output + "/refused", (path, success, detail) => {
            root.refusals.push({
                                 path: path,
                                 success: success,
                                 detail: detail
                               });
          });
        }
        const inline = Quickshell.env("IMAGE_DATA");
        const cancelled = ImageCacheService.retainImage(inline, root.output + "/cancelled", (path, success) => {
          root.cancelCallbacks.push({
                                      path: path,
                                      success: success
                                    });
        });
        cancelled.cancel();
        root.capture(inline, -1);
        producer.running = true;
      }
      if (root.producerDone && root.pending === 0 && root.results.length > 0 && !root.presented) {
        root.presented = true;
        for (const row of root.results) {
          if (row.success)
            resultFactory.createObject(presentations, {
                                         source: row.path,
                                         rowIndex: row.index,
                                         x: row.index * 64
                                       });
        }
      }
      if (root.presented && root.late.length === 4 && root.refusals.length === 3 && root.grabs === 0 && presentations.children.every(item => item.grabbed && !item.active)) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         raw: raw.status,
                                                         captured: root.captured,
                                                         results: root.results,
                                                         late: root.late,
                                                         bytes: root.byteControls,
                                                         refusals: root.refusals,
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
