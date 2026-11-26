pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons

// Policy only. Local inputs go straight to the decoder, while downloads get
// an owned temporary file. The renderer must retire it by releasing this
// scope; no path advertised by an old process can become a new source.
Scope {
  id: root

  property string source: ""
  property bool active: true
  property string revision: ""

  readonly property string state: _state
  readonly property string url: _url
  readonly property string errorCode: _code
  readonly property string errorReason: _reason
  readonly property int generation: _generation

  property string _state: "idle"
  property string _url: ""
  property string _code: ""
  property string _reason: ""
  property int _generation: 0
  property Process _download: null
  property bool _initialized: false

  function reset() {
    if (!_initialized)
      return;
    _url = "";
    _code = "";
    _reason = "";
    ++_generation;
    retire();
    if (!active || !source) {
      _state = "idle";
      return;
    }

    _state = "loading";
    if (source.startsWith("/")) {
      const local = PortalPaths.pathToUri(source);
      if (local.ok) {
        offer(local.uri);
        return;
      }
    } else if (/^file:/i.test(source)) {
      // Display sources can be Qt's pretty-decoded URL strings. Convert them
      // at this boundary without relaxing URI validation at the portal.
      const local = PortalPaths.qmlUrlToPath(source);
      if (local.ok) {
        offer(PortalPaths.pathToUri(local.path).uri);
        return;
      }
    } else if (/^(?:data:|image:\/\/)/i.test(source)) {
      offer(source);
      return;
    } else if (/^https?:\/\//i.test(source)) {
      _download = downloader.createObject(root, {
                                            requestedUrl: source,
                                            requestGeneration: _generation
                                          });
      if (_download) {
        _download.running = true;
        return;
      }
      fail("download-failed", "Could not start the image download");
      return;
    }
    fail("invalid-source", "Unsupported image source");
  }

  function offer(value) {
    _state = "ready";
    _url = value;
  }

  function fail(code, reason) {
    _url = "";
    _code = code;
    _reason = reason;
    _state = "unavailable";
  }

  function retire() {
    const previous = _download;
    _download = null;
    if (previous)
      previous.stdinEnabled = false;
  }

  onSourceChanged: reset()
  onActiveChanged: reset()
  onRevisionChanged: reset()
  Component.onCompleted: {
    _initialized = true;
    reset();
  }
  Component.onDestruction: retire()

  Component {
    id: downloader
    Process {
      id: download
      required property string requestedUrl
      required property int requestGeneration
      property bool announced: false
      property bool startedOnce: false

      workingDirectory: Quickshell.shellDir + "/Scripts/python/src"
      command: ["python3", "-B", "-m", "images.download", "--hold", requestedUrl, Settings.cacheDir]
      stdinEnabled: true
      stdout: SplitParser {
        onRead: line => {
          if (root._download !== download || root.generation !== download.requestGeneration || download.announced)
            return;
          let packet;
          try {
            packet = JSON.parse(line);
          } catch (_) {
            packet = null;
          }
          if (!packet || !PortalPaths.uriToPath(packet.source).ok) {
            root.retire();
            root.fail("download-failed", "The image download did not return a local file");
            return;
          }
          download.announced = true;
          root.offer(packet.source);
        }
      }
      onStarted: startedOnce = true
      onRunningChanged: {
        if (!running && !startedOnce) {
          if (root._download === download) {
            root._download = null;
            root.fail("download-failed", "Could not start the image download");
          }
          destroy();
        }
      }
      onExited: code => {
        if (root._download === download) {
          root._download = null;
          root.fail(code === 3 ? "source-too-large" : "download-failed", code === 3 ? "The image download exceeded the byte limit" : "Could not download the image");
        }
        destroy();
      }
    }
  }
}
