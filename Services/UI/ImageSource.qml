import QtQuick
import Quickshell
import "../../Helpers/PortalPaths.js" as PortalPaths
import qs.Services.UI

// One parent-bound subscription and one generation-fenced Qt handshake.
// Publishing a worker URL does not settle Ready: its renderer must load it.
Scope {
  id: root
  property string source: ""
  property bool active: true
  property string revision: ""
  property size requestedSize: Qt.size(128, 128)
  property string fit: "contain"
  property string animationIntent: "still"
  property bool normalize: false
  readonly property string state: _state
  readonly property int generation: _generation
  readonly property var candidate: _candidate
  readonly property var result: _result
  readonly property string errorCode: _result.code || ""
  readonly property string errorReason: _result.reason || ""
  readonly property string outputUrl: state === "ready" ? _result.url : ""
  property string _state: "idle"
  property int _generation: 0
  property int _serial: 0
  property string _token: ""
  property var _candidate: null
  property var _result: ({})
  property var _metadata: null
  property var _native: null
  property var _request: null
  property var _lifetime: ({
                             alive: true
                           })
  property bool _retry: false

  function _retire() {
    if (_token)
      ImageCacheService.releaseSource(_token);
    _token = "";
  }
  function _schedule() {
    ++_generation;
    _state = active && source ? "loading" : "idle";
    _retire();
    _candidate = null;
    _metadata = null;
    _native = null;
    _result = {};
    begin.restart();
  }
  function retry() {
    _retry = true;
    _schedule();
  }
  function _offer(url, origin, animated) {
    _native = null;
    _candidate = {
      url: url,
      origin: origin,
      animated: animated,
      generation: _generation,
      serial: ++_serial,
      width: _request.width,
      height: _request.height,
      retry: _request.retry
    };
  }
  function _unavailable(code, reason) {
    _state = "unavailable";
    _retire();
    _candidate = null;
    _result = {
      code: code,
      reason: reason
    };
  }
  function _subscribe(operation, callback) {
    _retire();
    var generation = _generation;
    var lifetime = _lifetime;
    _token = ImageCacheService.acquireSource(Object.assign({}, _request, {
                                                             operation: operation
                                                           }), function (reply) {
                                                             if (lifetime.alive && root._generation === generation && root.active)
                                                               callback(reply);
                                                           });
  }
  function _fallback() {
    if (!_candidate || _candidate.origin !== "native")
      return;
    if (_request.source.startsWith("image://")) {
      _unavailable("provider-failed", "The image provider could not supply this image");
      return;
    }
    _state = "loading";
    _candidate = null;
    _native = null;
    _subscribe("render", function (reply) {
      if (reply.status === "unavailable") {
        root._unavailable(reply.code, reply.reason);
        return;
      }
      root._metadata = reply;
      root._offer(reply.url, "fallback", reply.animated);
    });
  }
  function _settle() {
    if (!_native || !_metadata || !_candidate)
      return;
    if (_candidate.origin === "native" && animationIntent === "preserve" && _metadata.animated) {
      if (!_candidate.animated) {
        _offer(_candidate.url, "native", true);
        return;
      }
      if (_native.frames !== _metadata.frames) {
        _fallback();
        return;
      }
    }
    _result = Object.assign({}, _metadata, {
                              requestId: _metadata.id,
                              generation: _generation,
                              origin: _candidate.origin,
                              url: _candidate.url,
                              decodedWidth: _native.width,
                              decodedHeight: _native.height
                            });
    _state = "ready";
  }
  function report(ticket, status, width, height, frames) {
    if (!ticket || !_candidate || ticket.generation !== _generation || ticket.serial !== _candidate.serial || !active)
      return;
    if (status === Image.Error) {
      if (ticket.origin === "native")
        _fallback();
      else
        _unavailable("presentation-failed", "The decoded image could not be displayed");
    } else if (status === Image.Ready) {
      if (width < 1 || height < 1) {
        _unavailable("presentation-failed", "The image has no displayable pixels");
        return;
      }
      _native = {
        width: width,
        height: height,
        frames: frames
      };
      if (_request.source.startsWith("image://"))
        _metadata = {
          format: "provider",
          width: width,
          height: height,
          frames: 1,
          animated: false,
          delaysMs: [],
          loop: null
        };
      _settle();
    }
  }
  function _begin() {
    if (!active || !source)
      return;
    _request = {
      source: source,
      revision: revision,
      width: Math.max(1, Math.ceil(requestedSize.width)),
      height: Math.max(1, Math.ceil(requestedSize.height)),
      fit: fit,
      animationIntent: animationIntent,
      retry: _retry
    };
    _retry = false;
    var url = source;
    if (source.startsWith("/")) {
      var normalized = PortalPaths.pathToUri(source);
      if (!normalized.ok) {
        _unavailable("invalid-source", "The image path could not be read");
        return;
      }
      url = normalized.uri;
    }
    _offer(url, "native", false);
    if (normalize && !source.startsWith("image://")) {
      _fallback();
    } else if (!source.startsWith("image://")) {
      _subscribe("inspect", function (reply) {
        if (reply.status === "unavailable") {
          // A still Qt success does not prove motion preservation. Inspect or
          // normalize the content rather than trusting a filename/one frame.
          root._fallback();
          return;
        }
        root._metadata = reply;
        root._settle();
      });
    }
  }
  onSourceChanged: _schedule()
  onActiveChanged: _schedule()
  onRevisionChanged: _schedule()
  onRequestedSizeChanged: _schedule()
  onFitChanged: _schedule()
  onAnimationIntentChanged: _schedule()
  onNormalizeChanged: _schedule()
  Timer {
    id: begin
    interval: 0
    onTriggered: root._begin()
  }
  Component.onCompleted: _schedule()
  Component.onDestruction: {
    _lifetime.alive = false;
    begin.stop();
    _retire();
  }
}
