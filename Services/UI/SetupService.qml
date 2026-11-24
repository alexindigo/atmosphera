pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Services.UI

// Preparation belongs to the captured queue operation, not a wizard instance.
// Settings still owns retention/persistence and BindingsService owns Retry/FIFO.
Singleton {
  id: root

  function prepareCapturedSetup(work, complete, requestId) {
    var finished = false;
    function finish(result) {
      if (finished)
        return;
      finished = true;
      complete(result);
    }
    function save() {
      try {
        Settings.saveSetupWork(work, function (result) {
          if (result.status === "saved" || result.status === "nothing_to_save")
            Version.markChangelogSeen(Version.currentVersion);
          finish(result);
        }, requestId);
      } catch (error) {
        finish({
                 status: "failed",
                 error: {
                   code: "setup-save"
                 }
               });
      }
    }
    try {
      if (work.wallpaperDirectory !== Settings.data.wallpaper.directory) {
        Settings.data.wallpaper.directory = work.wallpaperDirectory;
        WallpaperService.refreshWallpapersList();
      }
      if (!work.wallpaper) {
        save();
        return;
      }
      WallpaperService.changeWallpaper(work.wallpaper, undefined, undefined, null, undefined, function (outcome) {
        if (outcome.state === "ready" && outcome.names.length === outcome.targets.length) {
          save();
        } else {
          var code = outcome.state === "ready" ? "superseded" : outcome.state === "cancelled" ? outcome.detail.code : "unavailable";
          finish({
                   status: "failed",
                   error: {
                     code: "setup-wallpaper-" + code,
                     imageCode: outcome.detail.code || "",
                     reason: outcome.detail.reason || ""
                   }
                 });
        }
      });
    } catch (error) {
      finish({
               status: "failed",
               error: {
                 code: "setup-save"
               }
             });
    }
  }
}
