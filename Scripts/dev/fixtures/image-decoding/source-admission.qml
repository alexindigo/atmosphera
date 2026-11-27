import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

ShellRoot {
  id: root
  property int tick: 0
  property bool retiring: false
  property bool capturing: false
  property bool registered: false
  property int settledTick: -1
  property int pending: 0
  property var terminalDetails: []
  property var settled: ({})

  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: {
      IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"));
      root.registered = true;
    }
  }

  function capture(item, name) {
    ++pending;
    if (!item.grabToImage(result => {
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: result.saveToFile(Quickshell.env("IMAGE_OUTPUT") + "/" + name + ".png")
                                                 }));
      --root.pending;
    })) {
      --pending;
      console.log("IMAGE_GRAB|" + JSON.stringify({
                                                   name: name,
                                                   saved: false
                                                 }));
    }
  }
  FloatingWindow {
    implicitWidth: 576
    implicitHeight: 96
    color: "#202020"
    visible: true
    Row {
      NImage {
        id: normalized
        width: 96
        height: 96
        source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp"
        normalize: true
        active: !root.retiring
      }
      NImage {
        id: thumbnail
        width: 96
        height: 96
        source: normalized.source
        thumbnail: true
        active: !root.retiring
      }
      NImage {
        id: synchronous
        width: 96
        height: 96
        source: Quickshell.env("IMAGE_SYNCHRONOUS_SOURCE")
        asynchronous: false
        active: !root.retiring
      }
      NImageIcon {
        id: declared
        width: 96
        height: 96
        source: Quickshell.env("IMAGE_REMOTE_URL") + "/declared"
        active: !root.retiring
        onStatusChanged: {
          if (status === Image.Error)
            root.terminalDetails.push({
                                        name: "declared",
                                        code: errorCode,
                                        reason: errorReason
                                      });
        }
      }
      NImageIcon {
        id: streamed
        width: 96
        height: 96
        source: Quickshell.env("IMAGE_REMOTE_URL") + "/streamed"
        active: !root.retiring
        onStatusChanged: {
          if (status === Image.Error)
            root.terminalDetails.push({
                                        name: "streamed",
                                        code: errorCode,
                                        reason: errorReason
                                      });
        }
      }
      NImage {
        id: valid
        width: 96
        height: 96
        source: Quickshell.env("IMAGE_REMOTE_URL") + "/valid"
        active: !root.retiring
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      ++root.tick;
      if (!root.capturing && root.registered && normalized.state === "ready" && thumbnail.state === "ready" && synchronous.state === "ready" && declared.status === Image.Error && streamed.status === Image.Error && valid.status === Image.Ready && root.settledTick < 0)
        root.settledTick = root.tick;
      if (!root.capturing && root.settledTick >= 0 && root.tick >= root.settledTick + 3) {
        root.settled = {
          normalized: normalized.state,
          thumbnail: thumbnail.state,
          synchronous: synchronous.state,
          formats: [normalized, thumbnail, synchronous].map(item => item.imageResult.format),
          extent: [synchronous.decodedSize.width, synchronous.decodedSize.height],
          declared: {
            failed: declared.failed,
            code: declared.errorCode,
            reason: declared.errorReason
          },
          streamed: {
            failed: streamed.failed,
            code: streamed.errorCode,
            reason: streamed.errorReason
          },
          valid: valid.imageState
        };
        root.capture(normalized, "normalized");
        root.capture(thumbnail, "thumbnail");
        root.capture(synchronous, "synchronous");
        root.capture(declared, "declared");
        root.capture(streamed, "streamed");
        root.capture(valid, "valid");
        root.capturing = true;
      }
      if (root.capturing && !root.pending)
        root.retiring = true;
      if (root.retiring && !root.pending) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         terminalDetails: root.terminalDetails,
                                                         settled: root.settled,
                                                         retired: [normalized, thumbnail, synchronous, declared, streamed, valid].map(item => ({
                                                           state: item.status === Image.Null ? "idle" : "not-idle",
                                                           status: item.status,
                                                           url: item.outputUrl || ""
                                                         }))
      }));
        Qt.quit();
      }
      if (root.tick >= 180)
        Qt.exit(3);
    }
  }
}
