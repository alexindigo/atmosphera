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
  property var candidates: []
  property var terminalDetails: []
  property var settled: ({})

  FileView {
    path: Quickshell.env("IMAGE_ICON_DIR") + "/icons.json"
    onLoaded: {
      IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("IMAGE_ICON_DIR"));
      root.registered = true;
    }
  }

  function candidate(handle, name) {
    var ticket = handle.candidate;
    if (!ticket)
      return;
    candidates.push({
                      name: name,
                      origin: ticket.origin
                    });
    Qt.callLater(() => handle.report(ticket, Image.Ready, 128, 128, 1));
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
  ImageSource {
    id: normalized
    source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp"
    normalize: true
    active: !root.retiring
    onCandidateChanged: root.candidate(normalized, "normalized")
  }
  ImageSource {
    id: thumbnail
    source: Quickshell.env("IMAGE_FIXTURES") + "/Still.webp"
    thumbnail: true
    active: !root.retiring
    onCandidateChanged: root.candidate(thumbnail, "thumbnail")
  }
  FloatingWindow {
    implicitWidth: 384
    implicitHeight: 96
    color: "#202020"
    visible: true
    Row {
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
          synchronousOrigin: synchronous.imageResult.origin,
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
        root.capture(declared, "declared");
        root.capture(streamed, "streamed");
        root.capture(valid, "valid");
        root.capturing = true;
      }
      if (root.capturing && !root.pending)
        root.retiring = true;
      if ((root.retiring && !root.pending && ImageCacheService.sourceInterestCount === 0 && !ImageCacheService.sourceWorkerRunning) || root.tick >= 180) {
        console.log("IMAGE_BASELINE|" + JSON.stringify({
                                                         candidates: root.candidates,
                                                         terminalDetails: root.terminalDetails,
                                                         settled: root.settled,
                                                         interests: ImageCacheService.sourceInterestCount,
                                                         requests: ImageCacheService.sourceRequestCount,
                                                         workerRunning: ImageCacheService.sourceWorkerRunning
                                                       }));
        Qt.quit();
      }
    }
  }
}
