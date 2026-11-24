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
  function sourceInterestSources() {
    return sourceWorker.interestSources();
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
  // The worker's still/video thumbnails and private representations live in
  // the freedesktop thumbnail folder (same environment as the worker).
  readonly property string thumbnailDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/thumbnails/"

  // True for a path this owner (or its pre-owner folders) generated: a
  // thumbnail or representation, never a user's original. Consumers that put
  // a thumbnail in place of a user's wallpaper use this to keep the two apart.
  function isGeneratedImage(path) {
    var local = String(path || "").replace(/^file:\/\//, "");
    return local !== "" && local.indexOf("/../") === -1 && [thumbnailDir, wpThumbDir, wpLargeDir].some(dir => local.indexOf(dir) === 0);
  }

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
  function retainImage(source, directory, width, height, callback, notification = false) {
    return retainedImage.createObject(root, {
                                        inputSource: String(source),
                                        destinationDirectory: String(directory),
                                        notification: notification,
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
      property bool notification: false
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
        try {
          // The receiving model takes its hold before the pending ticket ends.
          completed(success ? retainedResult.originalPath : "", success, detail);
        } finally {
          release();
          active = false;
          destroy();
        }
      }
      onStatusChanged: Qt.callLater(finish)
      Component.onCompleted: {
        token = root.acquireSource({
                                     source: inputSource,
                                     width: sourceSize.width,
                                     height: sourceSize.height,
                                     animationIntent: "still",
                                     operation: "retain",
                                     notification: notification,
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
    // Detach producer-owned pixels and local bytes before returning. Remote
    // locators are acquired asynchronously by the same retention owner.
    const captured = captureSource(imageUri);
    if (!captured.ok) {
      callback("", false, captured);
      return null;
    }
    return retainImage(captured.source, notificationsDir + "retained/", 64, 64, callback, true);
  }

  function openNotificationHistory(history, callback) {
    sourceWorker.openNotificationHistory(notificationsDir + "retained/", history, callback);
  }

  function updateNotificationHolders(paths, rows, callback) {
    sourceWorker.updateNotificationHolders(paths, rows, callback);
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
  // Representations are keyed by source content, stat identity, revision and
  // geometry, so a changed source never reuses an old entry. Invalidation and
  // clearing therefore share one owner-scoped operation: it removes unheld
  // positive and negative representations in this owner's private namespace,
  // keeps every representation a consumer (in any shell/lock process) still
  // holds, and never touches sources, retained originals, foreign freedesktop
  // thumbnails, another writer's staging or plugin-owned folders. Flat PNG
  // outputs of the retired pre-owner folders are removed too. The callback
  // receives {ok, removed, kept, refused} or {ok: false, code, reason}.
  function clearRepresentations(callback) {
    // Pre-owner shell outputs in these folders have no readers any more; the
    // plugin-owned subfolders of the thumbnail folder are not shell outputs.
    sourceWorker.clear([wpThumbDir, wpLargeDir, contributorsDir], callback);
  }

  function invalidateThumbnail(sourcePath, callback) {
    Logger.i("ImageCache", "Invalidating image representations");
    clearRepresentations(callback);
  }

  function invalidateLarge(sourcePath, callback) {
    Logger.i("ImageCache", "Invalidating image representations");
    clearRepresentations(callback);
  }

  function invalidateNotification(imageId) {
    // Labels are not content identities. Retained originals may still belong
    // to persisted history or another shell process; never unlink them here.
    Logger.d("ImageCache", "Notification retention is reference-owned; label invalidation ignored");
  }

  function invalidateAvatar(username, callback) {
    // A username is a label, never a cache path component.
    clearRepresentations(callback);
  }

  // -------------------------------------------------
  // Clear Cache Functions
  // -------------------------------------------------
  function clearAll(callback) {
    Logger.i("ImageCache", "Clearing image representations");
    clearRepresentations(callback);
  }

  function clearThumbnails(callback) {
    clearAll(callback);
  }

  function clearLarge(callback) {
    clearAll(callback);
  }

  function clearNotifications() {
    // Clearing representations must not destroy retained source bytes behind
    // live popups or cold history. History membership is owned by its service.
    Logger.i("ImageCache", "Preserving retained notification sources");
  }

  function clearContributors(callback) {
    clearAll(callback);
  }
}
