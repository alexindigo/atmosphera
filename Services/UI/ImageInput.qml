pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
  property var _releaseDownload: null
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
      const generation = _generation;
      _releaseDownload = ImageDownloads.acquire(source, reply => {
        if (root._generation !== generation)
          return;
        if (reply.source && PortalPaths.uriToPath(reply.source).ok)
          root.offer(reply.source);
        else {
          root.retire();
          root.fail(reply.code || "download-failed", reply.reason || "The image download did not return a local file");
        }
      });
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
    const release = _releaseDownload;
    _releaseDownload = null;
    release?.();
  }

  onSourceChanged: reset()
  onActiveChanged: reset()
  onRevisionChanged: reset()
  Component.onCompleted: {
    _initialized = true;
    reset();
  }
  Component.onDestruction: retire()
}
