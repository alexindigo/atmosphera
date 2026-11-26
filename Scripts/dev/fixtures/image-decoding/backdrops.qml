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
  readonly property string heldServer: Quickshell.env("IMAGE_HELD_SERVER")
  property int tick: 0
  property int pending: 0
  property var stages: []
  property bool done: false
  property string heldStep: "idle"
  property var heldStages: []

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
  function heldControl(path, next) {
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = () => {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      if (xhr.status !== 200) {
        Qt.exit(4);
        return;
      }
      root.heldStep = next;
    };
    xhr.open("GET", heldServer + path);
    xhr.send();
  }
  function observeHeld(name) {
    heldStages.push({
                      name: name,
                      backdrop: observe(backdrop),
                      lock: observe(lock)
                    });
  }
  function advanceHeld() {
    if (heldStep === "idle") {
      heldStep = "waiting";
      provider.replace(heldServer + "/held.png");
      heldControl("/admitted", "admitted");
    } else if (heldStep === "admitted" && backdrop.imageState === "loading" && lock.imageState === "loading") {
      observeHeld("admitted");
      heldStep = "replacing";
      provider.replace(inputs + "/frame-2.png");
    } else if (heldStep === "replacing" && backdrop.imageState === "ready" && lock.imageState === "ready") {
      observeHeld("before-release");
      heldStep = "capturing";
      grab(backdrop, "held-before-backdrop");
      grab(lock, "held-before-lock");
    } else if (heldStep === "capturing" && !pending) {
      heldStep = "releasing";
      heldControl("/release", "released");
    } else if (heldStep === "released") {
      // Let the completed response and the next frame run before checking
      // whether either consumer accepted pixels from the retired source.
      heldStep = "observing";
    } else if (heldStep === "observing") {
      observeHeld("after-release");
      heldStep = "done";
      grab(backdrop, "held-after-backdrop");
      grab(lock, "held-after-lock");
    }
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
      if (root.tick > 80 && !root.pending && root.heldServer && root.heldStep !== "done") {
        root.advanceHeld();
        return;
      }
      if (root.tick > 80 && !root.pending) {
        backdrop.visible = false;
        lock.visible = false;
      }
      if (root.tick >= 90 && !root.pending && backdrop.imageState === "idle" && lock.imageState === "idle") {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         stages: root.stages,
                                                         heldStages: root.heldStages,
                                                         hidden: {
                                                           backdrop: root.observe(backdrop),
                                                           lock: root.observe(lock)
                                                         },
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
    onTriggered: {
      console.log("IMAGE_TIMEOUT|" + root.heldStep + "|" + JSON.stringify(root.heldStages));
      Qt.exit(3);
    }
  }
}
