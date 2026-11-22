pragma Singleton

import QtQuick
import Quickshell
import "../../Helpers/ImageTypes.js" as ImageTypes
import "../../Helpers/PortalPaths.js" as PortalPaths
import "../../Helpers/sha256.js" as Checksum
import qs.Commons
import qs.Widgets

Singleton {
  id: root

  // -------------------------------------------------
  // Public Properties
  // -------------------------------------------------
  property bool initialized: false

  // Additive source protocol; legacy conversion adapters migrate cohort by
  // cohort, without switching existing consumers before their endpoint proof.
  readonly property bool sourceWorkerRunning: sourceWorker.running
  readonly property int sourceInterestCount: sourceWorker.interestCount
  readonly property int sourceRequestCount: sourceWorker.requestCount
  readonly property var sourceStatistics: sourceWorker.statistics
  signal sourceEvent(var event)
  function acquireSource(request, callback) {
    return sourceWorker.acquire(request, callback);
  }
  function releaseSource(token) {
    sourceWorker.release(token);
  }
  ImageWorker {
    id: sourceWorker
    onActivity: event => root.sourceEvent(event)
  }

  readonly property bool admissionReady: sourceAdmission.ready
  ImageAdmission {
    id: sourceAdmission
  }
  function captureSource(source) {
    return sourceAdmission.capture(source);
  }

  // Cache directories
  readonly property string baseDir: Settings.cacheDir + "images/"
  readonly property string wpThumbDir: baseDir + "wallpapers/thumbnails/"
  readonly property string wpLargeDir: baseDir + "wallpapers/large/"
  readonly property string notificationsDir: baseDir + "notifications/"
  readonly property string contributorsDir: baseDir + "contributors/"

  // Compatibility names describe recognition, never a guessed native reader.
  readonly property var basicImageFilters: ImageTypes.filters
  readonly property var extendedImageFilters: ImageTypes.filters
  readonly property var imageFilters: ImageTypes.filters

  // -------------------------------------------------
  // Signals
  // -------------------------------------------------
  signal cacheHit(string cacheKey, string cachedPath)
  signal cacheMiss(string cacheKey)
  signal processingComplete(string cacheKey, string cachedPath)
  signal processingFailed(string cacheKey, string error)

  // -------------------------------------------------
  // Initialization
  // -------------------------------------------------
  function init() {
    Logger.i("ImageCache", "Service started");
    createDirectories();
    cleanupOldCache();
    initialized = true;
  }

  function createDirectories() {
    Quickshell.execDetached(["mkdir", "-p", wpThumbDir]);
    Quickshell.execDetached(["mkdir", "-p", wpLargeDir]);
    Quickshell.execDetached(["mkdir", "-p", notificationsDir]);
    Quickshell.execDetached(["mkdir", "-p", contributorsDir]);
  }

  function cleanupOldCache() {
    // Notification retention has model-owned references and cannot be aged out
    // behind a still-persisted history entry. Its owner releases it explicitly.
    const dirs = [wpThumbDir, wpLargeDir, contributorsDir];
    dirs.forEach(function (dir) {
      Quickshell.execDetached(["find", dir, "-type", "f", "-mtime", "+15", "-delete"]);
    });
    Logger.d("ImageCache", "Cleanup triggered for files older than 15 days");
  }

  // -------------------------------------------------
  // Public API: Get Thumbnail (384x384)
  // -------------------------------------------------
  function getThumbnail(sourcePath, callback) {
    return requestImage(sourcePath, 384, 384, "cover", callback);
  }

  // -------------------------------------------------
  // Public API: Get Large Image (scaled to specified dimensions)
  // -------------------------------------------------
  function getLarge(sourcePath, width, height, callback) {
    return requestImage(sourcePath, width, height, "contain", callback, !Settings.data.wallpaper.useOriginalImages);
  }

  // Legacy callers receive a plain local path only after the shared renderer
  // acknowledges the validated representation. The returned interest can be
  // cancelled by a caller with a shorter lifetime than this singleton.
  function requestImage(sourcePath, width, height, transform, callback, normalize = true) {
    if (!sourcePath) {
      callback("", false, {
                 code: "empty-source",
                 reason: "No image was requested"
               });
      return null;
    }
    return callbackImage.createObject(root, {
                                        source: String(sourcePath),
                                        sourceSize: Qt.size(Math.max(1, Math.ceil(width)), Math.max(1, Math.ceil(height))),
                                        imageTransform: transform,
                                        normalize: normalize,
                                        completed: callback,
                                        requestKey: Checksum.sha256(JSON.stringify([String(sourcePath), width, height, transform]))
                                      });
  }

  // Retention uses the same preparation/decoder/cache owner, and keeps original
  // bytes separate from the still representation acknowledged by Qt.
  function retainImage(source, directory, width, height, callback) {
    return retainedImage.createObject(root, {
                                        inputSource: String(source),
                                        destinationDirectory: String(directory),
                                        sourceSize: Qt.size(Math.max(1, Math.ceil(width)), Math.max(1, Math.ceil(height))),
                                        completed: callback
                                      });
  }

  Component {
    id: retainedImage
    NImage {
      id: retained
      property string inputSource
      property string destinationDirectory
      property var completed
      property string token: ""
      property var retainedResult: null
      property bool settled: false
      visible: false
      animationIntent: "still"
      function cancel() {
        settled = true;
        active = false;
        release();
        destroy();
      }
      function release() {
        if (token)
          root.releaseSource(token);
        token = "";
      }
      function finish() {
        if (settled || !retainedResult)
          return;
        var failed = retainedResult.status === "unavailable";
        if (!failed && status !== Image.Ready && status !== Image.Error)
          return;
        settled = true;
        var success = !failed && status === Image.Ready;
        var detail = success || failed ? retainedResult : {
                                           code: errorCode,
                                           reason: errorReason
                                         };
        release();
        active = false;
        completed(success ? retainedResult.originalPath : "", success, detail);
        destroy();
      }
      onStatusChanged: Qt.callLater(finish)
      Component.onCompleted: {
        token = root.acquireSource({
                                     source: inputSource,
                                     width: sourceSize.width,
                                     height: sourceSize.height,
                                     animationIntent: "still",
                                     operation: "retain",
                                     destinationDirectory: destinationDirectory
                                   }, function (result) {
                                     retained.retainedResult = result;
                                     if (result.status !== "unavailable")
                                       retained.source = result.url;
                                     Qt.callLater(retained.finish);
                                   });
      }
      Component.onDestruction: release()
    }
  }

  Component {
    id: callbackImage
    NImage {
      id: request
      property var completed
      property string requestKey
      property bool settled: false
      normalize: true
      animationIntent: "still"
      visible: false
      function cancel() {
        settled = true;
        active = false;
        destroy();
      }
      onStatusChanged: Qt.callLater(finish)
      function finish() {
        if (settled || (status !== Image.Ready && status !== Image.Error))
          return;
        settled = true;
        const success = status === Image.Ready;
        const uri = success ? PortalPaths.uriToPath(outputUrl) : null;
        const path = uri && uri.ok ? uri.path : "";
        const detail = success ? imageResult : {
                                   code: errorCode,
                                   reason: errorReason
                                 };
        active = false;
        if (success && path)
          root.processingComplete(requestKey, path);
        else
          root.processingFailed(requestKey, detail.reason || "The decoded image is unavailable");
        completed(path, success && !!path, detail);
        destroy();
      }
    }
  }

  // -------------------------------------------------
  // Public API: Get Notification Icon (64x64)
  // -------------------------------------------------
  function getNotificationIcon(imageUri, appName, summary, callback) {
    // Capture before returning to the producer. Labels never identify bytes;
    // retention, validation, cancellation and Qt acceptance share one owner.
    const captured = captureSource(imageUri);
    if (!captured.ok) {
      callback("", false, captured);
      return null;
    }
    return retainImage(captured.source, notificationsDir + "retained/", 64, 64, callback);
  }

  // -------------------------------------------------
  // Public API: Get Circular Avatar (256x256)
  // -------------------------------------------------
  function getCircularAvatar(url, username, callback) {
    if (!url || !username) {
      callback("", false);
      return null;
    }
    return requestImage(url, 256, 256, "circle", callback);
  }

  // -------------------------------------------------
  // Cache Invalidation
  // -------------------------------------------------
  function invalidateThumbnail(sourcePath) {
    Logger.i("ImageCache", "Invalidating thumbnail for:", sourcePath);
    // Since cache keys include hash, we'd need to track mappings
    // For simplicity, clear all thumbnails
    clearThumbnails();
  }

  function invalidateLarge(sourcePath) {
    Logger.i("ImageCache", "Invalidating large for:", sourcePath);
    clearLarge();
  }

  function invalidateNotification(imageId) {
    // Labels are not content identities. Retained originals may still belong
    // to persisted history or another shell process; never unlink them here.
    Logger.d("ImageCache", "Notification retention is reference-owned; label invalidation ignored");
  }

  function invalidateAvatar(username) {
    const path = contributorsDir + username + "_circular.png";
    Quickshell.execDetached(["rm", "-f", path]);
  }

  // -------------------------------------------------
  // Clear Cache Functions
  // -------------------------------------------------
  function clearAll() {
    Logger.i("ImageCache", "Clearing all cache");
    clearThumbnails();
    clearLarge();
    clearNotifications();
    clearContributors();
  }

  function clearThumbnails() {
    Logger.i("ImageCache", "Clearing thumbnails cache");
    Quickshell.execDetached(["rm", "-rf", wpThumbDir]);
    Quickshell.execDetached(["mkdir", "-p", wpThumbDir]);
  }

  function clearLarge() {
    Logger.i("ImageCache", "Clearing large cache");
    Quickshell.execDetached(["rm", "-rf", wpLargeDir]);
    Quickshell.execDetached(["mkdir", "-p", wpLargeDir]);
  }

  function clearNotifications() {
    // Clearing representations must not destroy retained source bytes behind
    // live popups or cold history. History membership is owned by its service.
    Logger.i("ImageCache", "Preserving retained notification sources");
  }

  function clearContributors() {
    Logger.i("ImageCache", "Clearing contributors cache");
    Quickshell.execDetached(["rm", "-rf", contributorsDir]);
    Quickshell.execDetached(["mkdir", "-p", contributorsDir]);
  }
}
