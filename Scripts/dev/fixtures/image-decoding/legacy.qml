import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property var results: ({})
  property var completions: []
  property var failures: []
  property int pending: 0
  property int tick: 0
  property bool captured: false
  property bool cancelledCallback: false

  function receive(name, path, success, detail) {
    var result = Object.assign({}, results);
    result[name] = {
      path: path,
      success: success,
      detail: detail || {}
    };
    results = result;
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
  FloatingWindow {
    visible: true
    implicitWidth: 640
    implicitHeight: 160
    color: "transparent"
    Row {
      Repeater {
        id: images
        model: ["thumbnail", "large", "avatar", "misleading", "literal"]
        Image {
          required property string modelData
          width: 128
          height: 128
          fillMode: Image.PreserveAspectFit
          source: root.results[modelData] && root.results[modelData].success ? root.results[modelData].path : ""
        }
      }
    }
  }
  Connections {
    target: ImageCacheService
    function onProcessingComplete(key, path) {
      root.completions.push({
                              key: key,
                              path: path
                            });
    }
    function onProcessingFailed(key, reason) {
      root.failures.push({
                           key: key,
                           reason: reason
                         });
    }
  }
  Component.onCompleted: {
    ImageCacheService.init();
    Settings.data.wallpaper.useOriginalImages = Quickshell.env("IMAGE_USE_ORIGINAL") === "1";
    ImageCacheService.getThumbnail(inputs + "/Motion.webp", (path, success, detail) => root.receive("thumbnail", path, success, detail));
    ImageCacheService.getLarge(inputs + "/Motion.webp", 192, 128, (path, success, detail) => root.receive("large", path, success, detail));
    ImageCacheService.getCircularAvatar(inputs + "/Still.webp", "same-user", (path, success, detail) => root.receive("avatar", path, success, detail));
    ImageCacheService.getThumbnail(inputs + "/Misleading.png", (path, success, detail) => root.receive("misleading", path, success, detail));
    ImageCacheService.getThumbnail(inputs + "/bracket[0]: image.webp", (path, success, detail) => root.receive("literal", path, success, detail));
    ImageCacheService.getThumbnail(inputs + "/Corrupt.webp", (path, success, detail) => root.receive("corrupt", path, success, detail));
    ImageCacheService.getLarge(inputs + "/Missing.webp", 192, 128, (path, success, detail) => root.receive("missing", path, success, detail));
    var cancelled = ImageCacheService.getThumbnail(inputs + "/frame-2.png", () => root.cancelledCallback = true);
    if (cancelled)
      cancelled.cancel();
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (Object.keys(root.results).length !== 7 || root.tick < 40)
        return;
      if (!root.captured) {
        root.captured = true;
        for (var i = 0; i < images.count; ++i)
          root.grab(images.itemAt(i), images.itemAt(i).modelData);
        return;
      }
      if (root.pending || root.tick < 50)
        return;
      var readers = [];
      for (var j = 0; j < images.count; ++j) {
        const image = images.itemAt(j) as Image;
        readers.push({
                       name: image.modelData,
                       status: image.status
                     });
      }
      console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                       results: root.results,
                                                       readers: readers,
                                                       completions: root.completions,
                                                       failures: root.failures,
                                                       interests: ImageCacheService.sourceInterestCount,
                                                       requests: ImageCacheService.sourceRequestCount,
                                                       workerRunning: ImageCacheService.sourceWorkerRunning,
                                                       cancelledCallback: root.cancelledCallback
                                                     }));
      Qt.quit();
    }
  }
  Timer {
    interval: 20000
    running: true
    onTriggered: Qt.exit(3)
  }
}
