pragma ComponentBehavior: Bound
import ImvQml

import QtQuick
import qs.Services.UI

// Atmosphera presentation and input policy; ImvImage owns decoding, texture
// upload, animation, masks and request/cache lifetime.
Item {
  id: root

  property string source: ""
  property bool active: true
  property string sourceRevision: ""
  property string animationIntent: "still"
  property bool playing: true
  property bool paused: false
  property real roundedRadius: 0
  property real videoPosition: 0.1
  property int fillMode: Image.PreserveAspectFit
  property bool mirror: false
  property bool mirrorVertically: false
  property int horizontalAlignment: Image.AlignHCenter
  property int verticalAlignment: Image.AlignVCenter

  // Compatibility properties still accepted by shell and plugin callers.
  // The library selects decoder, orientation, cache policy and request size.
  property bool normalize: false
  property bool thumbnail: false
  property bool asynchronous: true
  property bool cache: true
  property bool mipmap: true
  property bool autoTransform: true
  property string imageTransform: fillMode === Image.PreserveAspectCrop ? "cover" : "contain"
  property var alphaMaskTint: null
  readonly property color _tint: alphaMaskTint ?? "transparent"
  property size sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
  property bool sizeToImage: false

  implicitWidth: !sizeToImage ? 0 : decodedSize.width || 1
  implicitHeight: !sizeToImage ? 0 : decodedSize.height || 1
  readonly property string imageState: input.state !== "ready" ? input.state : picture.status === ImvImage.Ready ? "ready" : picture.status === ImvImage.Failed ? "unavailable" : "loading"
  state: imageState
  readonly property int status: imageState === "ready" ? Image.Ready : imageState === "unavailable" ? Image.Error : imageState === "loading" ? Image.Loading : Image.Null
  readonly property string errorCode: input.errorCode || picture.errorCode
  readonly property string errorReason: input.errorReason || picture.errorDetail
  readonly property var imageResult: Object.assign({
                                                     animated: frameCount > 1
                                                   }, picture.sourceInfo)
  readonly property string outputUrl: status === Image.Ready ? input.url : ""
  readonly property int generation: input.generation
  readonly property size decodedSize: Qt.size(picture.sourceInfo.width || 0, picture.sourceInfo.height || 0)
  readonly property int frameCount: picture.sourceInfo.frames || 0
  readonly property real _fitScale: decodedSize.width > 0 && decodedSize.height > 0 ? Math.min(width / decodedSize.width, height / decodedSize.height) : 0
  readonly property real paintedWidth: !decodedSize.width ? 0 : fillMode === Image.PreserveAspectFit ? decodedSize.width * _fitScale : width
  readonly property real paintedHeight: !decodedSize.height ? 0 : fillMode === Image.PreserveAspectFit ? decodedSize.height * _fitScale : height
  readonly property Item textureItem: texture
  property bool textureOnly: false

  function retry() {
    if (input.url)
      ImvCache.invalidate(input.url);
    input.reset();
  }

  ImageInput {
    id: input
    source: root.source
    active: root.active
    revision: root.sourceRevision
  }

  ImvImage {
    id: picture
    readonly property bool alignedFit: root.fillMode === Image.PreserveAspectFit && (root.horizontalAlignment !== Image.AlignHCenter || root.verticalAlignment !== Image.AlignVCenter)
    width: alignedFit && root.paintedWidth ? root.paintedWidth : root.width
    height: alignedFit && root.paintedHeight ? root.paintedHeight : root.height
    x: root.horizontalAlignment === Image.AlignRight ? root.width - width : root.horizontalAlignment === Image.AlignLeft ? 0 : (root.width - width) / 2
    y: root.verticalAlignment === Image.AlignBottom ? root.height - height : root.verticalAlignment === Image.AlignTop ? 0 : (root.height - height) / 2
    source: input.url
    fillMode: root.fillMode === Image.PreserveAspectCrop ? ImvImage.Cover : root.fillMode === Image.PreserveAspectFit ? ImvImage.Contain : ImvImage.Stretch
    animate: root.animationIntent === "preserve"
    playing: root.playing && !root.paused
    smooth: root.smooth
    videoPosition: root.videoPosition
    mask: root.roundedRadius > 0 ? ImvImage.Rounded : ImvImage.NoMask
    radius: root.roundedRadius
    tint: root._tint
    // ImvImage.tint sets RGB while preserving source alpha. The shell's
    // source-in policy also scales the resulting opacity by tint alpha.
    opacity: root.alphaMaskTint === null ? 1 : root._tint.a

    transform: Scale {
      origin.x: picture.width / 2
      origin.y: picture.height / 2
      xScale: root.mirror ? -1 : 1
      yScale: root.mirrorVertically ? -1 : 1
    }
  }

  ShaderEffectSource {
    id: texture
    sourceItem: picture
    hideSource: root.textureOnly
    visible: false
  }
}
