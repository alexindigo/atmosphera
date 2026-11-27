import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Wallpaper
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property var modelData: Quickshell.screens[0]
  property int tick: 0
  property int pending: 0
  property var snapshots: []
  property var afterCapture: null
  property var previews: []
  Component {
    id: previewTrack
    QtObject {
      required property QtObject item
    }
  }
  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"))
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
    item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(root.output + "/" + name + ".png")
                                                 }));
      --root.pending;
      if (!root.pending && root.afterCapture) {
        var next = root.afterCapture;
        root.afterCapture = null;
        Qt.callLater(next);
      }
    });
  }
  function sample(cohort, index) {
    var content = panel.contentItem;
    var grid = cohort === "local" ? content.screenRepeater.itemAt(0).gridView : content.wallhavenView.gridView;
    var tile = grid.itemAtIndex(index);
    var image = find(tile, item => "imagePath" in item);
    if (!previews.some(track => track.item === image))
      previews.push(previewTrack.createObject(root, {
                                                item: image
                                              }));
    snapshots.push({
                     cohort: cohort,
                     index: index,
                     tick: tick,
                     source: image.imagePath,
                     status: image.status,
                     animationIntent: image.animationIntent,
                     reason: image.errorReason
                   });
    grab(image, cohort + "-image-" + index + "-" + tick);
    if (index === 1)
      grab(tile, cohort + "-failure-tile");
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    color: "#202020"
    WallpaperPanel {
      id: panel
      screen: root.modelData
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    Settings.data.general.animationDisabled = true;
    Settings.data.wallpaper.useWallhaven = false;
    Settings.data.wallpaper.viewMode = "single";
    Qt.callLater(() => panel.open());
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 10) {
        WallpaperService.wallpaperLists = {
          [root.modelData.name]: [root.inputs + "/Motion.webp", root.inputs + "/Corrupt.webp", root.inputs + "/Still.heic"]
        };
        WallpaperService.wallpaperListChanged(root.modelData.name, 3);
      } else if (root.tick >= 25 && root.tick <= 35) {
        root.sample("local", 0);
        if (root.tick === 25) {
          root.sample("local", 1);
          root.sample("local", 2);
        }
      } else if (root.tick === 40) {
        root.grab(panel, "local-panel");
        root.afterCapture = function () {
          Settings.data.general.animationDisabled = false;
          Settings.data.wallpaper.useWallhaven = true;
          WallhavenService.searchCompleted([
                                             {
                                               id: "motion",
                                               thumbs: {
                                                 large: Quickshell.env("IMAGE_GALLERY_URL") + "/motion.jpg"
                                               }
                                             },
                                             {
                                               id: "bad",
                                               thumbs: {
                                                 large: Quickshell.env("IMAGE_GALLERY_URL") + "/bad.jpg"
                                               }
                                             },
                                             {
                                               id: "heic",
                                               thumbs: {
                                                 large: Quickshell.env("IMAGE_GALLERY_URL") + "/heic.jpg"
                                               }
                                             }
                                           ], {});
        };
      } else if (root.tick >= 65 && root.tick <= 75) {
        root.sample("remote", 0);
        if (root.tick === 65) {
          root.sample("remote", 1);
          root.sample("remote", 2);
        }
      } else if (root.tick === 80) {
        root.grab(panel, "remote-panel");
        root.afterCapture = function () {
          panel.close();
        };
      } else if (root.tick >= 100 && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         snapshots: root.snapshots,
                                                         retired: root.previews.every(track => !track.item || track.item.imageState === "idle"),
                                                         warningColor: [Math.round(AtmoColor.mError.r * 255), Math.round(AtmoColor.mError.g * 255), Math.round(AtmoColor.mError.b * 255), 255]
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
