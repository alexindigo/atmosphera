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
  readonly property string outputUrl: image.outputUrl
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
      // Keep the item in the scene graph during upload, but do not show it
      // behind the fallback or before presentation has been acknowledged.
      opacity: root._presentable ? 1 : 0
      source: root.imagePath
      sourceRevision: root.sourceRevision
      active: root.active && !!root.imagePath
      normalize: root.normalize
      animationIntent: root.animationIntent
      paused: root.paused || !root.visible || Settings.data.general.animationDisabled
      roundedRadius: root._innerRadius
      fillMode: root.imageFillMode
      smooth: true
      antialiasing: true
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
