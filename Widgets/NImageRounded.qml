import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
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

  readonly property bool _isAnimated: !!image.imageResult.animated
  readonly property QtObject imageSource: image
  readonly property bool showFallback: fallbackIcon !== "" && (imagePath === "" || status === Image.Error)
  readonly property int status: image.status
  readonly property string imageState: image.imageState
  readonly property string errorCode: image.errorCode
  readonly property string errorReason: image.errorReason
  readonly property var imageResult: image.imageResult
  readonly property int currentFrame: image.currentFrame
  readonly property string outputUrl: image.outputUrl

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
      visible: false
      source: root.imagePath
      sourceRevision: root.sourceRevision
      active: root.active && !!root.imagePath
      normalize: root.normalize
      animationIntent: root.animationIntent
      paused: root.paused || !root.visible || Settings.data.general.animationDisabled
      // The rounded shader owns fit/crop. Capture the full source texture so
      // that a second crop/letterbox cannot be applied by the shared item.
      fillMode: Image.Stretch
      imageTransform: "contain"
      mipmap: true
      smooth: true
      antialiasing: true
    }

    ShaderEffect {
      anchors.fill: parent
      anchors.margins: root.borderWidth
      visible: !root.showFallback && root.status === Image.Ready
      property var source: image.textureItem
      property real itemWidth: width
      property real itemHeight: height
      property real sourceWidth: image.decodedSize.width
      property real sourceHeight: image.decodedSize.height
      property real cornerRadius: Math.max(0, root.radius - root.borderWidth)
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
