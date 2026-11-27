import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.NotificationHistory
import qs.Services.System
import qs.Services.UI

ShellRoot {
  id: root
  readonly property var modelData: Quickshell.screens[0]
  property int tick: 0
  property int pending: 0
  property bool sampled: false
  property var rows: []
  property var widgets: []
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
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
  function collect(item, result) {
    if ("notification" in item && "imagePath" in item) {
      result.push(item);
      return;
    }
    for (var i = 0; item.children && i < item.children.length; ++i)
      collect(item.children[i], result);
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 2) {
        Settings.data.general.animationDisabled = true;
        history.open();
      }
      if (root.tick > 20 && !root.sampled) {
        var images = [];
        collect(history, images);
        if (images.length === 2 && images.every(item => item.status === Image.Ready)) {
          root.sampled = true;
          for (var i = 0; i < NotificationService.historyModel.count; ++i)
            root.rows.push(Object.assign({}, NotificationService.historyModel.get(i)));
          images.forEach((item, index) => {
            var row = {
              summary: item.notification.summary,
              status: item.status,
              path: item.imagePath,
              file: "cold-" + index + ".png"
            };
            root.widgets.push(row);
            ++root.pending;
            item.grabToImage(image => {
              console.log("IMAGE_GRAB|" + JSON.stringify({
                                                           name: row.file,
                                                           saved: image.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/" + row.file)
                                                         }));
              --root.pending;
            });
          });
        }
      }
      if (root.sampled && !root.pending) {
        history.close();
        const interests = Object.values(NotificationService.popupState).reduce((sum, entry) => sum + entry.imageRequests.filter(request => request.pending).length, 0);
        if (!interests) {
          console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                           rows: root.rows,
                                                           widgets: root.widgets,
                                                           interests: interests
                                                         }));
          Qt.quit();
        }
      }
    }
  }
  Timer {
    interval: 23000
    running: true
    onTriggered: Qt.exit(2)
  }
}
