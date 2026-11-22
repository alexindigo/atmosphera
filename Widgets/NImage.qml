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
  property bool playing: true
  property bool paused: false
  property int fillMode: Image.PreserveAspectFit
  property string imageTransform: fillMode === Image.PreserveAspectCrop ? "cover" : "contain"
  property bool asynchronous: true
  property bool cache: true
  property bool mipmap: true
  property bool autoTransform: true
  property bool mirror: false
  property size sourceSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)), Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
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
    animationIntent: root.animationIntent
    normalize: root.normalize
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
        sourceComponent = ticket.animated ? moving : still;
        active = true;
      }
    }
    active: false
    visible: root.imageState === "ready"
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
      onStatusChanged: handle.report(ticket, status, implicitWidth, implicitHeight, frameCount)
      Component.onCompleted: {
        ticket = renderer.ticket;
        handle.report(ticket, status, implicitWidth, implicitHeight, frameCount);
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
