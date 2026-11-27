pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string fixture: Quickshell.env("ATMO_RETENTION_FIXTURE")
  property string retainedPath: ""
  property bool failed: false
  property bool producerDeleted: false
  property bool historySaved: false
  property string expectedHash: ""

  function reject(reason) {
    failed = true;
    console.error("IMV_RETENTION FAIL", reason);
    Qt.exit(3);
  }

  function finish() {
    if (!producerDeleted || !historySaved || failed)
      return;
    ImageCacheService.clearRepresentations(result => {
      if (!result.ok) {
        root.reject(result.reason);
        return;
      }
      digest.running = true;
    });
  }

  Component.onCompleted: {
    ImageCacheService.init();
    ImageCacheService.openNotificationHistory(fixture + "/history.json", ok => {
      if (!ok) {
        reject("Could not open fixture history");
        return;
      }
      ImageCacheService.getNotificationIcon(fixture + "/producer.svg", (path, success, detail) => {
        if (!success || detail.originalFormat !== "svg") {
          reject(JSON.stringify(detail));
          return;
        }
        retainedPath = path;
        expectedHash = detail.contentSha256;
        ImageCacheService.updateNotificationHolders([path], [
                                                      {
                                                        cachedImage: path
                                                      }
                                                    ], saved => {
                                                      if (!saved) {
                                                        reject("History did not acquire the original");
                                                        return;
                                                      }
                                                      root.historySaved = true;
                                                      root.finish();
                                                    });
      });
      unlink.running = true;
    });
  }

  Process {
    id: unlink
    command: ["rm", "--", root.fixture + "/producer.svg"]
    onExited: code => {
      if (code !== 0) {
        root.reject("Could not unlink the producer file");
        return;
      }
      root.producerDeleted = true;
      root.finish();
    }
  }
  Process {
    id: digest
    command: ["sha256sum", "--", root.retainedPath]
    stdout: StdioCollector {
      id: output
    }
    onExited: code => {
      if (code !== 0 || !root.expectedHash || output.text.trim().split(/\s+/, 1)[0] !== root.expectedHash) {
        root.reject("Could not read the same retained bytes after eviction");
        return;
      }
      console.log("IMV_RETENTION PASS", root.retainedPath, root.expectedHash);
      Qt.quit();
    }
  }
  Timer {
    interval: 12000
    running: true
    onTriggered: root.reject("Timed out")
  }
}
