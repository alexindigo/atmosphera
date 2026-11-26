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

  function reject(reason) {
    failed = true;
    console.error("IMV_RETENTION FAIL", reason);
    Qt.exit(3);
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
        ImageCacheService.updateNotificationHolders([path], [
                                                      {
                                                        cachedImage: path
                                                      }
                                                    ], saved => {
                                                      if (!saved) {
                                                        reject("History did not acquire the original");
                                                        return;
                                                      }
                                                      ImageCacheService.clearRepresentations(() => {
                                                        console.log("IMV_RETENTION PASS", path, detail.contentSha256);
                                                        Qt.quit();
                                                      });
                                                    });
      });
      unlink.running = true;
    });
  }

  Process {
    id: unlink
    command: ["rm", "--", root.fixture + "/producer.svg"]
  }
  Timer {
    interval: 12000
    running: true
    onTriggered: root.reject("Timed out")
  }
}
