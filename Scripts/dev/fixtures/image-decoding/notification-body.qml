import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Notification as Popups
import qs.Modules.Panels.NotificationHistory
import qs.Services.System
import qs.Services.UI

// A notification whose summary and body carry <img>, a Markdown image and an
// HTML background, through the actual service, popup and history panel. The
// service keeps stripping images from bodies (orchestrator decision): the
// text survives and nothing creates image work.
ShellRoot {
  id: root
  readonly property var modelData: Quickshell.screens[0]
  property int tick: 0
  property bool started: false
  property int shownTick: -1
  property int producerExit: -1
  property string producerErrors: ""
  property var result: null
  Popups.Notification {
    id: popups
  }
  FloatingWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 1000
    NotificationHistoryPanel {
      id: history
      screen: root.modelData
    }
  }
  function rows(model) {
    var found = [];
    for (var i = 0; i < model.count; ++i)
      found.push(Object.assign({}, model.get(i)));
    return found;
  }
  function texts(item, found) {
    if (!item)
      return found;
    if ("imageStates" in item && "parsedContent" in item && String(item.text).indexOf("marker") !== -1)
      found.push({
                   text: String(item.text),
                   images: item.imageCount,
                   visible: item.visible
                 });
    for (var i = 0; item.children && i < item.children.length; ++i)
      texts(item.children[i], found);
    return found;
  }
  Process {
    id: producer
    stdinEnabled: true
    command: ["python3", Quickshell.env("IMAGE_PRODUCER"), Quickshell.env("IMAGE_HTTP_BASE")]
    stdout: SplitParser {
      onRead: data => root.shownTick = root.tick
    }
    stderr: StdioCollector {}
    onExited: code => {
      root.producerExit = code;
      root.producerErrors = stderr.text;
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (!root.started && NotificationService.notificationServerLoader) {
        root.started = true;
        Settings.data.general.animationDisabled = true;
        Settings.data.notifications.saveToHistory.normal = true;
        history.open();
        producer.running = true;
      }
      // Settled: the popup and history show it, and a few ticks passed for any
      // (unwanted) image work to start.
      if (!root.result && root.shownTick >= 0 && root.tick > root.shownTick + 20) {
        var popupItem = popups.instances.length && popups.instances[0].item ? popups.instances[0].item.contentItem : null;
        root.result = {
          popupModel: rows(NotificationService.popupModel),
          historyModel: rows(NotificationService.historyModel),
          popupTexts: texts(popupItem, []),
          historyTexts: texts(history, [])
        };
        history.grabToImage(image => {
          console.log("IMAGE_GRAB|" + JSON.stringify({
                                                       name: "history-panel",
                                                       saved: image.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/history-panel.png")
                                                     }));
          producer.write("close\n");
        });
      }
      if (root.result && root.producerExit >= 0) {
        history.close();
        NotificationService.performSaveHistory();
        console.log("IMAGE_BASELINE|" + JSON.stringify(Object.assign({
                                                                       producerExit: root.producerExit,
                                                                       producerErrors: root.producerErrors,
                                                                       historyFile: NotificationService.historyFile
                                                                     }, root.result)));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 40000
    running: true
    onTriggered: Qt.exit(2)
  }
}
