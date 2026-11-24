pragma ComponentBehavior: Bound

import QtQuick
import qs.Services.UI

// The shared Qt decode/presentation boundary. Each renderer captures its ticket
// at creation; a retired source/mode/size cannot acknowledge a later generation.
Item {
  id: root
  property string source: ""
  property bool active: true
  property string sourceRevision: ""
  property string animationIntent: "still"
  property bool normalize: false
  property bool thumbnail: false
  // Optional still-image presentation: fit and tint the decoded alpha mask.
  property var alphaMaskTint: null
  readonly property bool _alphaMask: alphaMaskTint !== null && animationIntent === "still"
  // Optional rounded presentation for the software scene graph. Provider
  // pixmaps stay in process; file and network sources use the worker owner.
  property real roundedRadius: 0
  readonly property bool _roundedProvider: roundedRadius > 0 && source.startsWith("image://")
  readonly property bool _raster: _alphaMask || _roundedProvider
  on_RasterChanged: renderer.replace()
  property bool playing: true
  property bool paused: false
  property int fillMode: Image.PreserveAspectFit
  property string imageTransform: fillMode === Image.PreserveAspectCrop ? "cover" : "contain"
  property bool asynchronous: true
  property bool cache: true
  property bool mipmap: true
  property bool autoTransform: true
  property bool mirror: false
  property bool mirrorVertically: false
  property int horizontalAlignment: Image.AlignHCenter
  property int verticalAlignment: Image.AlignVCenter
  property size sourceSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)), Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
  // Opt-in natural sizing (like a plain Image without width/height): the
  // implicit size is the decoded size. Set sourceSize as the upper bound.
  property bool sizeToImage: false
  implicitWidth: sizeToImage ? decodedSize.width : 0
  implicitHeight: sizeToImage ? decodedSize.height : 0
  readonly property string imageState: handle.state
  state: imageState
  readonly property int status: ({
                                   idle: Image.Null,
                                   loading: Image.Loading,
                                   ready: Image.Ready,
                                   unavailable: Image.Error
                                 })[imageState]
  readonly property string errorCode: handle.errorCode
  readonly property string errorReason: handle.errorReason
  readonly property var imageResult: handle.result
  readonly property string outputUrl: handle.outputUrl
  readonly property int generation: handle.generation
  readonly property Image _renderer: renderer.item as Image
  readonly property real paintedWidth: _renderer ? _renderer.paintedWidth : 0
  readonly property real paintedHeight: _renderer ? _renderer.paintedHeight : 0
  readonly property int currentFrame: _renderer ? _renderer.currentFrame : 0
  readonly property int frameCount: _renderer ? _renderer.frameCount : 0
  // Consumers sample this supported texture surface, never reach into children.
  readonly property Item textureItem: texture
  readonly property size decodedSize: _renderer ? Qt.size(_renderer.implicitWidth, _renderer.implicitHeight) : Qt.size(0, 0)

  function retry() {
    handle.retry();
  }

  ImageSource {
    id: handle
    source: root.source
    active: root.active
    revision: root.sourceRevision
    requestedSize: root.sourceSize
    fit: root.imageTransform
    roundedRadius: root._roundedProvider ? 0 : Math.round(Math.max(0, root.roundedRadius) * Screen.devicePixelRatio)
    animationIntent: root.animationIntent
    normalize: root.normalize
    thumbnail: root.thumbnail
  }

  Loader {
    id: renderer
    anchors.fill: parent
    property var ticket: null
    function replace() {
      // Deactivate even when the Component type is unchanged. A fresh renderer
      // has immutable request identity, including for A -> B -> A replacements.
      active = false;
      ticket = handle.candidate;
      if (ticket) {
        sourceComponent = root._raster ? mask : (ticket.animated ? moving : still);
        active = true;
      }
    }
    active: false
    visible: root._raster || root.imageState === "ready"
  }
  Connections {
    target: handle
    function onCandidateChanged() {
      renderer.replace();
    }
  }

  Component {
    id: still
    Image {
      id: image
      property var ticket: null
      source: ticket ? ticket.url : ""
      sourceSize: ticket ? Qt.size(ticket.width, ticket.height) : Qt.size(1, 1)
      fillMode: root.fillMode
      asynchronous: root.asynchronous
      cache: root.cache && !root.sourceRevision && !(ticket && ticket.retry)
      mipmap: root.mipmap
      smooth: root.smooth
      autoTransform: root.autoTransform
      mirror: root.mirror
      mirrorVertically: root.mirrorVertically
      horizontalAlignment: root.horizontalAlignment
      verticalAlignment: root.verticalAlignment
      onStatusChanged: handle.report(ticket, status, implicitWidth, implicitHeight, frameCount)
      Component.onCompleted: {
        ticket = renderer.ticket;
        handle.report(ticket, status, implicitWidth, implicitHeight, frameCount);
      }
    }
  }
  Component {
    id: mask
    Canvas {
      id: maskCanvas
      contextType: "2d"
      property var ticket: null
      property bool reported: false
      readonly property color tint: root.alphaMaskTint ?? "transparent"
      readonly property bool admitted: root.imageState === "ready"
      readonly property real radius: Math.min(root.roundedRadius, width / 2, height / 2)
      readonly property int fillMode: root._roundedProvider ? root.fillMode : Image.PreserveAspectFit

      function begin(): void {
        if (!available || !ticket)
          return;
        // This is the owner renderer for the ticket, not a copy of a rendered
        // item. Qt manages the pixmap load without a scene-graph readback.
        loadImage(ticket.url, Qt.size(ticket.width, ticket.height));
        requestPaint();
      }

      Component.onCompleted: {
        ticket = renderer.ticket;
        begin();
      }
      onAvailableChanged: begin()
      onImageLoaded: requestPaint()
      onAdmittedChanged: requestPaint()
      onTintChanged: requestPaint()
      onRadiusChanged: requestPaint()
      onFillModeChanged: requestPaint()
      onContextChanged: {
        if (context)
          requestPaint();
      }

      onPaint: {
        // Qt can dispatch a dirty paint before delayed context creation.
        // Context creation requeues paint without touching the pixmap ticket.
        const ctx = context;
        if (!ctx)
          return;
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        if (!ticket)
          return;
        const url = ticket.url.toString();
        if (isImageError(url)) {
          if (!reported) {
            reported = true;
            handle.report(ticket, Image.Error, 0, 0, 0);
          }
          return;
        }
        if (!isImageLoaded(url))
          return;
        // Reads the pixmap already loaded in this Canvas, without another decode.
        const pixels = ctx.createImageData(url);
        if (!reported) {
          reported = true;
          handle.report(ticket, Image.Ready, pixels.width, pixels.height, 1);
        }
        if (!admitted || pixels.width < 1 || pixels.height < 1)
          return;
        const sx = width / pixels.width;
        const sy = height / pixels.height;
        const scale = fillMode === Image.PreserveAspectCrop ? Math.max(sx, sy) : Math.min(sx, sy);
        const w = fillMode === Image.Stretch ? width : pixels.width * scale;
        const h = fillMode === Image.Stretch ? height : pixels.height * scale;
        if (radius > 0) {
          ctx.beginPath();
          ctx.roundedRect(0, 0, width, height, radius, radius);
          ctx.clip();
        }
        ctx.drawImage(pixels, (width - w) / 2, (height - h) / 2, w, h);
        // Raster composition also works with the software scene graph.
        if (root._alphaMask) {
          ctx.globalCompositeOperation = "source-in";
          ctx.fillStyle = tint;
          ctx.fillRect(0, 0, width, height);
        }
      }
    }
  }
  Component {
    id: moving
    AnimatedImage {
      property var ticket: null
      source: ticket ? ticket.url : ""
      sourceSize: ticket ? Qt.size(ticket.width, ticket.height) : Qt.size(1, 1)
      fillMode: root.fillMode
      asynchronous: root.asynchronous
      cache: root.cache && !root.sourceRevision && !(ticket && ticket.retry)
      mipmap: root.mipmap
      smooth: root.smooth
      autoTransform: root.autoTransform
      mirror: root.mirror
      mirrorVertically: root.mirrorVertically
      horizontalAlignment: root.horizontalAlignment
      verticalAlignment: root.verticalAlignment
      playing: root.playing
      paused: root.paused
      onStatusChanged: handle.report(ticket, status, implicitWidth, implicitHeight, frameCount)
      Component.onCompleted: {
        ticket = renderer.ticket;
        handle.report(ticket, status, implicitWidth, implicitHeight, frameCount);
      }
    }
  }
  ShaderEffectSource {
    id: texture
    sourceItem: root._renderer
    visible: false
    live: true
  }
}
