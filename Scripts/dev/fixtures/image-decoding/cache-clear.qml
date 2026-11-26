import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings.Tabs.Wallpaper
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property bool clicked: false
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int phase: 0
  property bool pending: false
  property var probes: ({})
  property var toasts: []
  property string retained: ""

  function findButton(item, label) {
    if (item.text === label && typeof item.clicked === "function")
      return item;
    for (const child of item.children || []) {
      const found = findButton(child, label);
      if (found)
        return found;
    }
    return null;
  }
  function capture(item, label) {
    pending = true;
    if (!item.grabToImage(frame => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: label,
                                                   saved: frame.saveToFile(root.output + "/" + label + ".png")
                                                 }));
      root.pending = false;
    }))
      Qt.exit(3);
  }
  function probe(label) {
    pending = true;
    scan.label = label;
    scan.running = true;
  }

  Component.onCompleted: {
    ImageCacheService.init();
    ImageCacheService.openNotificationHistory(root.inputs + "/clear-history.json", opened => {
      if (!opened) {
        Qt.exit(3);
        return;
      }
      ImageCacheService.getNotificationIcon(root.inputs + "/Still.webp", (path, ok) => {
        if (!ok) {
          Qt.exit(3);
          return;
        }
        ImageCacheService.updateNotificationHolders([path], [
                                                      {
                                                        cachedImage: path
                                                      }
                                                    ], saved => {
                                                      if (saved)
                                                        root.retained = path;
                                                      else
                                                        Qt.exit(3);
                                                    });
      });
    });
  }

  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toasts.push({
                         title: title,
                         type: type,
                         phase: root.phase
                       });
    }
  }
  Process {
    id: scan
    property string label
    command: ["find", Settings.cacheDir + "images/decoded", "-type", "f", "-name", "*.imvqoi", "-printf", "%P\n"]
    stdout: StdioCollector {
      id: inventory
    }
    onExited: code => {
      if (code !== 0) {
        Qt.exit(3);
        return;
      }
      root.probes[label] = inventory.text.trim().split("\n").filter(path => path !== "").sort();
      root.pending = false;
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 720
    implicitHeight: 720
    NImage {
      id: held
      width: 96
      height: 96
      source: root.inputs + "/Still.webp"
      active: root.phase < 4
    }
    NImage {
      id: released
      width: 96
      height: 96
      x: 96
      source: root.inputs + "/frame-1.png"
      active: root.phase === 0 || root.phase >= 5
    }
    Loader {
      id: settings
      y: 100
      width: 600
      active: root.phase >= 1
      sourceComponent: GeneralSubTab {}
    }
  }
  Timer {
    running: true
    repeat: true
    interval: 150
    onTriggered: {
      if (root.pending)
        return;
      if (root.phase === 0 && root.retained && held.status === Image.Ready && released.status === Image.Ready) {
        root.phase = 1;
        root.probe("populated");
      } else if (root.phase === 1 && released.status === Image.Null && settings.item) {
        const button = root.findButton(settings.item, I18n.tr("panels.wallpaper.settings-clear-cache-button"));
        if (!button) {
          Qt.exit(3);
          return;
        }
        root.phase = 2;
        root.clicked = true;
        button.clicked();
        root.probe("cleared");
      } else if (root.phase === 2) {
        // clear() queues eviction. Observe its result, not the first scan
        // after the synchronous call, which can race the cache worker.
        if (root.probes.cleared.length) {
          root.probe("cleared");
        } else if (held.status === Image.Ready) {
          root.phase = 3;
          root.capture(held, "held-after-clear");
        }
      } else if (root.phase === 3) {
        root.phase = 4;
      } else if (root.phase === 4 && held.status === Image.Null) {
        root.phase = 5;
      } else if (root.phase === 5 && released.status === Image.Ready) {
        root.phase = 6;
        root.capture(released, "regenerated");
      } else if (root.phase === 6) {
        root.phase = 7;
        root.probe("regenerated");
      } else if (root.phase === 7) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         clicked: root.clicked,
                                                         probes: root.probes,
                                                         retained: root.retained,
                                                         toasts: root.toasts
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.log("IMAGE_TIMEOUT|cache-clear|" + root.phase + "|" + held.status + "|" + released.status);
      Qt.exit(3);
    }
  }
}
