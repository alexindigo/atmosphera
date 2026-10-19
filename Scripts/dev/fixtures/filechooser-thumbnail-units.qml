import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Files

ShellRoot {
  id: root
  property string base: Quickshell.env("FILECHOOSER_THUMBNAIL_ROOT")
  property int phase: 0
  property int ticks: 0
  property int failures: 0
  FileThumbnails { id: provider }
  FileThumbnail { id: first; provider: provider; pixels: 128; path: root.base + "/A space résumé.mp4"; stamp: "one" }
  FileThumbnail { id: second; provider: provider; pixels: 128; path: first.path; stamp: first.stamp }
  function check(name, condition) {
    if (!condition) ++failures;
    Logger.i("ThumbnailUnits", "THUMBNAIL_QML|" + JSON.stringify({case: name, pass: !!condition}));
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 300) {
        root.check("deadline", false);
        Qt.quit();
      }
      if (root.phase === 0) {
        root.check("lazy-worker", !provider.running);
        first.active = true; second.active = true;
        root.phase = 1;
      } else if (root.phase === 1 && first.url && second.url) {
        root.check("streaming-URL-consumer", first.url === second.url && first.url.startsWith("file://"));
        root.check("deduplicated-decode", provider.statistics.ffmpeg === 1 && provider.statistics.generated === 1);
        first.active = false;
        root.phase = 2;
      } else if (root.phase === 2) {
        root.check("one-subscriber-retains-result", first.url === "" && second.url !== "");
        second.active = false;
        root.phase = 3;
      } else if (root.phase === 3 && Object.keys(provider.urls).length === 0) {
        first.active = true;
        root.phase = 4;
      } else if (root.phase === 4 && first.url) {
        root.check("revisit-cache-no-decoder", provider.statistics.ffmpeg === 1 && provider.statistics.hit === 1);
        first.path = root.base + "/Corrupt.mp4";
        root.phase = 5;
      } else if (root.phase === 5 && provider.statistics.failed === 1) {
        root.check("failure-is-none", first.url === "");
        first.path = root.base + "/Hanging.mp4";
        root.phase = 6;
        root.ticks = 0;
      } else if (root.phase === 6 && root.ticks >= 10) {
        first.active = false;
        root.phase = 7;
      } else if (root.phase === 7 && provider.statistics.cancelled > 0) {
        root.check("dropped-interest-cancels", first.url === "" && provider.statistics.failed === 1);
        provider.enabled = false;
        root.phase = 8;
      } else if (root.phase === 8 && !provider.running) {
        root.check("picker-close-reaps-helper", true);
        Logger.i("ThumbnailUnits", "THUMBNAIL_QML|" + JSON.stringify({complete: true, failures: root.failures}));
        Qt.quit();
      }
    }
  }
}
