import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  readonly property string inputs: Quickshell.env("IMAGE_FIXTURES")
  readonly property string output: Quickshell.env("IMAGE_OUTPUT")
  property int tick: 0
  property bool admitted: false
  property int pendingGrabs: 0
  property var events: []
  property var samples: []
  property var settled: null
  property bool staleRejected: false
  property var staleTicket: null
  property int sharingBefore: 0
  property int sharingAfter: 0
  property int pausedFrame: -1
  property bool pausePreserved: false
  property var formats: ["Still.webp", "Misleading.png", "Still.avif", "Still.heic", "Multipage.tiff", "Oriented.jpg", "bracket[0]: image.webp", "Space \u6d77\u5cb8.webp", "Still.svg"]

  function grab(item, name) {
    ++pendingGrabs;
    if (!item.grabToImage(result => {
      var saved = result.saveToFile(output + "/" + name + ".png");
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: saved
                                                 }));
      --root.pendingGrabs;
    })) {
      --pendingGrabs;
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: false
                                                 }));
    }
  }
  function describe(item) {
    return {
      state: item.state,
      status: item.status,
      errorCode: item.errorCode,
      errorReason: item.errorReason,
      url: item.outputUrl,
      result: item.imageResult,
      generation: item.generation,
      frameCount: item.frameCount,
      paintedWidth: item.paintedWidth,
      paintedHeight: item.paintedHeight
    };
  }
  ImageSource {
    id: fencing
    source: root.inputs + "/Still.webp"
    active: false
  }
  FloatingWindow {
    implicitWidth: 1200
    implicitHeight: 640
    visible: true
    color: "#202020"
    Row {
      Repeater {
        id: tiles
        model: root.formats
        NImage {
          required property string modelData
          width: 120
          height: 96
          source: root.inputs + "/" + modelData
          sourceSize: Qt.size(128, 128)
        }
      }
    }
    Image {
      id: raw
      y: 110
      width: 96
      height: 64
      source: "file://" + root.inputs + "/Still.webp"
    }
    NImage {
      id: motion
      x: 110
      y: 110
      width: 192
      height: 128
      source: root.inputs + "/Motion.webp"
      sourceSize: Qt.size(192, 128)
      animationIntent: "preserve"
      onCurrentFrameChanged: {
        if (state === "ready") {
          root.events.push({
                             frame: currentFrame,
                             atMs: Date.now()
                           });
          if (root.tick > 12 && root.tick < 38)
            root.grab(motion, "motion-" + root.events.length + "-" + currentFrame);
        }
      }
    }
    NImage {
      id: firstFrame
      x: 320
      y: 110
      width: 192
      height: 128
      source: root.inputs + "/Motion.webp"
      sourceSize: Qt.size(192, 128)
      animationIntent: "still"
      normalize: true
    }
    NImage {
      id: sharedA
      x: 530
      y: 110
      width: 128
      height: 128
      source: root.inputs + "/Still.webp"
      sourceSize: Qt.size(128, 128)
      normalize: true
    }
    NImage {
      id: sharedB
      x: 670
      y: 110
      width: 128
      height: 128
      source: root.inputs + "/Still.webp"
      sourceSize: Qt.size(128, 128)
      normalize: true
    }
    NImage {
      id: replacing
      x: 810
      y: 110
      width: 128
      height: 128
      source: root.inputs + "/Still.webp"
      sourceSize: Qt.size(128, 128)
    }
    NImage {
      id: corrupt
      y: 260
      width: 128
      height: 128
      source: root.inputs + "/Corrupt.webp"
    }
    NImage {
      id: missing
      x: 140
      y: 260
      width: 128
      height: 128
      source: root.inputs + "/Missing.webp"
    }
    NImage {
      id: provider
      x: 280
      y: 260
      width: 128
      height: 128
      source: "image://missing-image-test/texture"
      sourceRevision: "1"
    }
    NImage {
      id: disabled
      x: 420
      y: 260
      width: 128
      height: 128
      source: root.inputs + "/Still.webp"
      active: false
    }
    NImage {
      id: data
      x: 560
      y: 260
      width: 128
      height: 128
      source: Quickshell.env("IMAGE_DATA")
    }
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      // Capture outcomes after the actual consumers settle, never after a
      // guessed decoder delay. The independent watchdog still fails a stall.
      if (!root.admitted) {
        var ready = [motion, firstFrame, sharedA, sharedB, replacing, data].every(item => item.status === Image.Ready);
        for (var index = 0; index < tiles.count; ++index) {
          const tile = tiles.itemAt(index) as NImage;
          ready = ready && tile.status === Image.Ready;
        }
        if (!ready)
          return;
        root.admitted = true;
      }
      ++root.tick;
      root.samples.push({
                          tick: root.tick,
                          frame: motion.currentFrame,
                          state: motion.state,
                          frames: motion.frameCount
                        });
      if (root.tick === 12) {
        for (var i = 0; i < tiles.count; ++i)
          root.grab(tiles.itemAt(i), "format-" + i);
        root.grab(firstFrame, "first-frame");
        root.sharingBefore = ImageCacheService.sourceRequestCount;
        sharedA.active = false;
        replacing.source = root.inputs + "/frame-1.png";
        fencing.active = true;
      }
      if (root.tick === 15) {
        root.sharingAfter = ImageCacheService.sourceRequestCount;
        root.staleTicket = fencing.candidate;
        fencing.source = root.inputs + "/frame-2.png";
        fencing.report(root.staleTicket, Image.Ready, 128, 128, 1);
        root.staleRejected = fencing.state !== "ready";
      }
      if (root.tick === 20) {
        motion.paused = true;
        root.pausedFrame = motion.currentFrame;
      }
      if (root.tick === 25) {
        root.pausePreserved = motion.imageState === "ready" && motion.currentFrame === root.pausedFrame && motion.imageResult.frames === 3;
        motion.paused = false;
      }
      if (root.tick === 30) {
        root.grab(sharedB, "shared-survivor");
        root.grab(replacing, "replacing");
        root.grab(data, "data");
      }
      if (root.tick === 40) {
        root.settled = {
          formats: root.formats.map((name, i) => ({
            name: name,
            consumer: root.describe(tiles.itemAt(i))
          })),
        raw: raw.status,
        motion: root.describe(motion),
        firstFrame: root.describe(firstFrame),
        sharedA: root.describe(sharedA),
        sharedB: root.describe(sharedB),
        replacing: root.describe(replacing),
        corrupt: root.describe(corrupt),
        missing: root.describe(missing),
        provider: root.describe(provider),
        disabled: root.describe(disabled),
        data: root.describe(data),
        events: root.events,
        samples: root.samples,
        staleRejected: root.staleRejected,
        sharingBefore: root.sharingBefore,
        sharingAfter: root.sharingAfter,
        pausePreserved: root.pausePreserved,
        stats: ImageCacheService.sourceStatistics
      };
      for (var j = 0; j < tiles.count; ++j) {
        const tile = tiles.itemAt(j) as NImage;
        tile.active = false;
      }
      for (var item of [motion, firstFrame, sharedB, replacing, corrupt, missing, provider, data, fencing])
        item.active = false;
    }
    if (root.tick >= 50 && root.pendingGrabs === 0) {
      root.settled.finalInterests = ImageCacheService.sourceInterestCount;
      root.settled.finalRequests = ImageCacheService.sourceRequestCount;
      root.settled.workerRunning = ImageCacheService.sourceWorkerRunning;
      console.log("IMAGE_BASELINE|" + JSON.stringify(root.settled));
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
