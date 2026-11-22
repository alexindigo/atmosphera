import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Notification as Popups
import qs.Modules.Panels.NotificationHistory
import qs.Services.System
import qs.Services.UI

ShellRoot {
  id: root
  readonly property var modelData: Quickshell.screens[0]
  property int tick: 0
  property int producedAt: -1
  property bool started: false
  property bool sampled: false
  property bool closing: false
  property int pending: 0
  property int producerExit: -1
  property string producerErrors: ""
  property var result: ({})
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
  }
  Popups.Notification {
    id: popups
  }
  FloatingWindow {
    visible: true
    implicitWidth: 800
    implicitHeight: 800
    NotificationHistoryPanel {
      id: history
      screen: Quickshell.screens[0]
    }
  }
  Process {
    id: producer
    stdinEnabled: true
    command: ["python3", Quickshell.env("IMAGE_PRODUCER"), Quickshell.env("IMAGE_FIXTURES")]
    stdout: SplitParser {
      onRead: data => {
        root.producedAt = root.tick;
        history.open();
      }
    }
    stderr: StdioCollector {}
    onExited: code => {
      root.producerExit = code;
      root.producerErrors = stderr.text;
    }
  }
  function find(item, accept) {
    if (accept(item))
      return item;
    for (var i = 0; item.children && i < item.children.length; ++i) {
      var found = find(item.children[i], accept);
      if (found)
        return found;
    }
    return null;
  }
  function grab(item, name) {
    ++pending;
    item.grabToImage(image => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: image.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/" + name + ".png")
                                                 }));
      --root.pending;
    });
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (!root.started && NotificationService.notificationServerLoader && ImageCacheService.admissionReady) {
        root.started = true;
        Settings.data.general.animationDisabled = true;
        Settings.data.notifications.respectExpireTimeout = true;
        Settings.data.notifications.saveToHistory.normal = true;
        producer.running = true;
      }
      if (!root.sampled && root.producedAt >= 0 && root.tick > root.producedAt + 25) {
        var window = popups.instances[0].item;
        var popupImage = find(window.contentItem, item => "imagePath" in item && item.visible);
        var historyImage = find(history, item => "imagePath" in item);
        root.result = {
          popup: {
            status: popupImage.status,
            source: popupImage.imagePath
          },
          history: {
            status: historyImage.status,
            source: historyImage.imagePath
          },
          entry: Object.assign({}, NotificationService.historyModel.get(0))
        };
        grab(popupImage, "popup-original-loss");
        grab(historyImage, "history-original-loss");
        root.sampled = true;
      }
      if (root.sampled && !root.pending && !root.closing) {
        root.closing = true;
        producer.write("close\n");
      }
      if (root.sampled && !root.pending && root.producerExit >= 0) {
        root.result.producerExit = root.producerExit;
        root.result.producerErrors = root.producerErrors;
        console.log("IMAGE_BASELINE|" + JSON.stringify(root.result));
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
