import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI

Item {
  id: root

  property real radius: 0
  property string imagePath: ""
  property string fallbackIcon: ""
  property real fallbackIconSize: Style.fontSizeXXL
  property real borderWidth: 0
  property color borderColor: "transparent"
  property int imageFillMode: Image.PreserveAspectCrop
  property bool active: true
  property bool paused: false
  property bool normalize: false
  property string sourceRevision: ""
  property string animationIntent: "preserve"
  // An upstream source owner can fail before a URL exists (for example when
  // a notification producer cannot be captured). Present that failure too.
  property string sourceFailureCode: ""
  property string sourceFailureReason: ""

  readonly property bool _isAnimated: !!image.imageResult.animated
  readonly property QtObject imageSource: image
  readonly property bool showFallback: fallbackIcon !== "" && (imagePath === "" || status === Image.Error)
  readonly property int status: sourceFailureCode ? Image.Error : image.status
  readonly property string imageState: sourceFailureCode ? "unavailable" : image.imageState
  readonly property string errorCode: sourceFailureCode || image.errorCode
  readonly property string errorReason: sourceFailureCode ? sourceFailureReason : image.errorReason
  readonly property var imageResult: image.imageResult
  readonly property int currentFrame: image.currentFrame
  readonly property string outputUrl: image.outputUrl
  readonly property bool _software: GraphicsInfo.api === GraphicsInfo.Software
  readonly property bool _presentable: !showFallback && status === Image.Ready
  readonly property real _innerRadius: Math.max(0, radius - borderWidth)

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.width: root.borderWidth
    border.color: root.borderColor

    NImage {
      id: image
      anchors.fill: parent
      anchors.margins: root.borderWidth
      visible: root._software && root._presentable
      source: root.imagePath
      sourceRevision: root.sourceRevision
      active: root.active && !!root.imagePath
      normalize: root.normalize
      animationIntent: root.animationIntent
      paused: root.paused || !root.visible || Settings.data.general.animationDisabled
      // The RHI shader fits and clips the texture. On software the owner
      // renders fitted, rounded pixels before the scene graph paints them.
      roundedRadius: root._software ? root._innerRadius : 0
      fillMode: root._software ? root.imageFillMode : Image.Stretch
      imageTransform: roundedRadius <= 0 ? "contain" : root.imageFillMode === Image.PreserveAspectCrop ? "cover" : root.imageFillMode === Image.PreserveAspectFit ? "contain" : "stretch"
      mipmap: true
      smooth: true
      antialiasing: true
    }

    ShaderEffect {
      anchors.fill: parent
      anchors.margins: root.borderWidth
      visible: !root._software && root._presentable
      property var source: image.textureItem
      property real itemWidth: width
      property real itemHeight: height
      property real sourceWidth: image.decodedSize.width
      property real sourceHeight: image.decodedSize.height
      property real cornerRadius: root._innerRadius
      property real imageOpacity: 1.0
      property int fillMode: root.imageFillMode

      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/rounded_image.frag.qsb")
      supportsAtlasTextures: false
      blending: true
    }

    AtmoIcon {
      anchors.fill: parent
      anchors.margins: root.borderWidth
      visible: root.showFallback
      icon: root.fallbackIcon
      pointSize: root.fallbackIconSize
    }
    AtmoIcon {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: root.status === Image.Error
      icon: Icon.warning
      pointSize: Math.min(Style.fontSizeM, root.width / 3)
      color: AtmoColor.mError
      Accessible.name: I18n.tr("widgets.file-picker.preview-unavailable")
      Accessible.description: root.errorReason
    }
    HoverHandler {
      onHoveredChanged: {
        if (hovered && root.status === Image.Error)
          TooltipService.show(root, I18n.tr("widgets.file-picker.preview-unavailable") + ": " + root.errorReason);
        else
          TooltipService.hide();
      }
    }
  }
}
