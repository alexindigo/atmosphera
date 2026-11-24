import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings.Tabs.Wallpaper
import qs.Services.UI
import qs.Widgets

// Actual wallpaper settings "Clear cache" button against the image owner: a
// held representation, a released legacy-adapter representation and retired
// pre-owner folders. Files are probed by path, never through the owner.
ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string legacyDir: Settings.cacheDir + "images/wallpapers/"
  readonly property bool ownerClear: typeof ImageCacheService.clearRepresentations === "function"
  property int tick: 0
  property int phase: 0
  property int pending: 0
  property var released: null
  property var toasts: []
  property var probes: ({})
  property var clearResult: null
  property var heldState: ({})
  property var regenerated: ({})
  property bool clicked: false

  function find(item, text) {
    if (!item)
      return null;
    if (item.text === text && typeof item.clicked === "function")
      return item;
    var children = item.children || [];
    for (var i = 0; i < children.length; ++i) {
      var found = find(children[i], text);
      if (found)
        return found;
    }
    return null;
  }
  function probe(name, path) {
    ++pending;
    probeComponent.createObject(root, {
                                  name: name,
                                  command: ["test", "-e", path]
                                });
  }
  function grab(item, name) {
    if (!item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
    })) {
      root.fail("Grab rejected: " + name);
      return;
    }
    ++pending;
  }
  function fail(message) {
    console.error("CACHE_CLEAR|" + message);
    Qt.exit(2);
  }
  function state(image) {
    return {
      status: image.status,
      url: image.outputUrl,
      path: String(image.outputUrl).replace(/^file:\/\//, "")
    };
  }

  Component {
    id: probeComponent
    Process {
      property string name
      running: true
      onExited: code => {
        if (code !== 0 && code !== 1) {
          root.fail("Probe failed: " + name + " (exit " + code + ")");
          return;
        }
        var probes = Object.assign({}, root.probes);
        probes[name] = code === 0;
        root.probes = probes;
        --root.pending;
        destroy();
      }
    }
  }
  Component {
    id: heldComponent
    NImage {
      width: 96
      height: 96
      normalize: true
      sourceSize: Qt.size(96, 96)
      source: root.inputs + "/Still.webp"
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toasts = root.toasts.concat([
                                         {
                                           title: title,
                                           description: description,
                                           type: type,
                                           phase: root.phase
                                         }
                                       ]);
    }
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 720
    implicitHeight: 720
    color: "transparent"
    Row {
      Item {
        id: slot
        width: 96
        height: 96
      }
      Item {
        id: again
        width: 96
        height: 96
      }
    }
    Loader {
      id: settings
      y: 100
      width: 600
      active: root.phase >= 1
      sourceComponent: GeneralSubTab {}
    }
  }
  property Item held: null
  Component.onCompleted: {
    ImageCacheService.init();
    Settings.data.wallpaper.useOriginalImages = false;
    held = heldComponent.createObject(slot);
    ImageCacheService.getLarge(inputs + "/Motion.webp", 192, 128, (path, success, detail) => root.released = {
      path: path,
      success: success
    });
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.pending)
        return;
      if (root.phase === 0) {
        if (!root.released || root.held.status !== Image.Ready)
          return;
        if (!root.released.success || !root.released.path) {
          root.fail("Released representation was not produced");
          return;
        }
        root.heldState = root.state(root.held);
        root.probe("releasedBeforeButton", root.released.path);
        root.phase = 1;
      } else if (root.phase === 1) {
        if (!root.probes.releasedBeforeButton) {
          root.fail("Released representation missing before clear");
          return;
        }
        var button = root.find(settings.item, I18n.tr("panels.wallpaper.settings-clear-cache-button"));
        if (!button)
          return;
        root.clicked = true;
        button.clicked();
        root.phase = 2;
      } else if (root.phase === 2) {
        if (!root.toasts.length)
          return;
        root.probe("heldAfterButton", root.heldState.path);
        root.probe("releasedAfterButton", root.released.path);
        root.probe("legacyAfterButton", root.legacyDir + "large/legacy-key.png");
        root.probe("pluginAfterButton", root.legacyDir + "thumbnails/mpvpaper/plugin.bmp");
        root.grab(root.held, "held-after-clear");
        root.heldState = Object.assign({}, root.heldState, {
                                         statusAfterButton: root.held.status
                                       });
        root.phase = root.ownerClear ? 3 : 9;
      } else if (root.phase === 3) {
        // The last interest retires; the same owner operation then removes it
        // and a new consumer regenerates rather than inheriting a failure.
        root.held.destroy();
        root.phase = 31;
      } else if (root.phase === 31) {
        ImageCacheService.clearRepresentations(result => root.clearResult = result);
        root.phase = 4;
      } else if (root.phase === 4) {
        if (!root.clearResult)
          return;
        root.probe("heldAfterRelease", root.heldState.path);
        root.phase = 41;
      } else if (root.phase === 41) {
        if (root.probes.heldAfterRelease !== false) {
          root.fail("Held representation still exists after release and clear");
          return;
        }
        root.held = heldComponent.createObject(again);
        root.phase = 5;
      } else if (root.phase === 5) {
        if (root.held.status !== Image.Ready && root.held.status !== Image.Error)
          return;
        root.regenerated = root.state(root.held);
        root.probe("regeneratedExists", root.regenerated.path);
        root.grab(root.held, "regenerated");
        root.phase = 9;
      } else if (root.phase === 9) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         ownerClear: root.ownerClear,
                                                         clicked: root.clicked,
                                                         toasts: root.toasts,
                                                         held: root.heldState,
                                                         released: root.released,
                                                         probes: root.probes,
                                                         clearResult: root.clearResult,
                                                         regenerated: root.regenerated
                                                       }));
        root.held.destroy();
        settings.active = false;
        root.phase = 10;
      } else if (root.phase === 10) {
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
