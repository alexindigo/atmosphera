import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.LockScreen
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property int pending: 0
  property var stages: []
  property bool done: false

  QtObject {
    id: provider
    property bool isInitialized: true
    property string path: root.inputs + (Quickshell.env("IMAGE_INITIAL_BAD") === "1" ? "/Corrupt.webp" : "/Motion.webp")
    signal wallpaperChanged(string screenName, string path)
    function getWallpaper(name) {
      return path;
    }
    function isSolidColorPath(value) {
      return value.startsWith("solid://");
    }
    function replace(value) {
      path = value;
      wallpaperChanged(Quickshell.screens[0].name, path);
    }
  }
  function grab(item, name) {
    ++pending;
    item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    });
  }
  function observe(item) {
    return {
      resolved: item.resolvedWallpaperPath,
      state: "imageState" in item ? item.imageState : "legacy",
      reason: "errorReason" in item ? item.errorReason : ""
    };
  }
  function capture(name) {
    stages.push({
                  name: name,
                  backdrop: observe(backdrop),
                  lock: observe(lock)
                });
    grab(backdrop, name + "-backdrop");
    grab(lock, name + "-lock");
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 400
    implicitHeight: 200
    Row {
      Item {
        width: 192
        height: 128
        AtmoWallpaperBackground {
          id: backdrop
          screen: Quickshell.screens[0]
          wallpaperProvider: provider
        }
      }
      Item {
        width: 192
        height: 128
        LockScreenBackground {
          id: lock
          screen: Quickshell.screens[0]
          wallpaperProvider: provider
        }
      }
    }
    TextInput {
      id: input
      y: 150
      focus: true
      text: "unlock-input-control"
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 30) {
        root.capture("before");
        provider.replace(root.inputs + "/Corrupt.webp");
      }
      if (root.tick === 55) {
        root.capture("failed");
        provider.replace(root.inputs + "/Motion.webp");
        provider.replace(root.inputs + "/frame-1.png");
      }
      if (root.tick === 80) {
        root.capture("replacement");
      }
      if (root.tick > 80 && !root.pending) {
        backdrop.visible = false;
        lock.visible = false;
      }
      if (root.tick >= 90 && !root.pending && !ImageCacheService.sourceWorkerRunning) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         stages: root.stages,
                                                         interests: ImageCacheService.sourceInterestCount,
                                                         requests: ImageCacheService.sourceRequestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning,
                                                         inputFocused: input.activeFocus,
                                                         inputText: input.text
                                                       }));
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 20000
    running: true
    onTriggered: Qt.exit(3)
  }
}
