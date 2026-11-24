import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  readonly property string monitor: Quickshell.screens[0].name
  property int tick: 0
  property int stage: 0
  property var snapshots: []
  property var events: []
  property var counts: []
  property var browse: []
  function snapshot(name) {
    snapshots.push({
                     name: name,
                     paths: WallpaperService.getWallpapersList(monitor).slice(),
                     count: WallpaperService.scanningCount
                   });
  }
  function setPools(ids) {
    Settings.data.wallpaper.monitorPools = [
          {
            name: monitor,
            pools: ids.map(id => ({
              id: id,
              active: true,
              rotate: true
            }))
  }
        ];
  }
  function finish() {
    proof.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   saved: result.saveToFile(root.output + "/scan.png")
                                                 }));
      console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                       snapshots: root.snapshots,
                                                       events: root.events,
                                                       counts: root.counts,
                                                       browse: root.browse
                                                     }));
      Qt.quit();
    });
  }
  FloatingWindow {
    visible: true
    implicitWidth: 128
    implicitHeight: 128
    Rectangle {
      id: proof
      anchors.fill: parent
      color: "#cc1828"
    }
  }
  Connections {
    target: WallpaperService
    function onWallpaperListChanged(screenName, count) {
      if (screenName === root.monitor)
        root.events.push({
                           stage: root.stage,
                           count: count,
                           paths: WallpaperService.getWallpapersList(screenName).slice()
                         });
    }
    function onScanningCountChanged() {
      root.counts.push({
                         stage: root.stage,
                         count: WallpaperService.scanningCount
                       });
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    Settings.data.wallpaper.viewMode = "single";
    Settings.data.wallpaper.directory = inputs + "/scan-main";
    WallpaperProviderRegistry.registerPool("scan-simple", {
                                             id: "scan-simple",
                                             label: "Simple",
                                             source: "plugin",
                                             dir: inputs + "/pool-simple"
                                           });
    root.setPools(["scan-simple"]);
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (root.tick === 10) {
        root.stage = 1;
        WallpaperService.refreshWallpapersList();
      } else if (root.tick === 30) {
        root.snapshot("union");
        if (Quickshell.env("IMAGE_SCAN_BASELINE") === "1") {
          root.finish();
          stop();
          return;
        }
        root.stage = 2;
        WallpaperService.refreshWallpapersList();
      } else if (root.tick === 31) {
        WallpaperService.scanDirectoryWithDirs(root.monitor, root.inputs + "/browse-only", result => root.browse = result.files);
      } else if (root.tick === 50) {
        root.snapshot("browse");
        root.stage = 3;
        root.setPools(["scan-simple", "scan-literal"]);
        WallpaperProviderRegistry.registerPool("scan-literal", {
                                                 id: "scan-literal",
                                                 label: "Literal",
                                                 source: "plugin",
                                                 dir: root.inputs + "/" + Quickshell.env("IMAGE_SCAN_POOL")
                                               });
      } else if (root.tick === 70) {
        root.snapshot("literal");
        root.stage = 4;
        WallpaperService.refreshWallpapersList();
        root.setPools([]);
        Settings.data.wallpaper.directory = root.inputs + "/scan-next";
        WallpaperService.refreshWallpapersList();
      } else if (root.tick === 90) {
        root.snapshot("latest");
        root.stage = 5;
        Settings.data.wallpaper.directory = root.inputs + "/empty";
        WallpaperService.refreshWallpapersList();
      } else if (root.tick === 110) {
        root.snapshot("empty");
        root.finish();
      }
    }
  }
  Timer {
    interval: 18000
    running: true
    onTriggered: Qt.exit(3)
  }
}
