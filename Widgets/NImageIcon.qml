import QtQuick
import qs.Commons

// Image presentation with the labelled failure badge (icons, logos, tray and
// menu textures, plugin previews) through the shared image owner. Name lookup
// stays with the caller; this component only presents a resolved source.
Item {
  id: root

  property string source: ""
  property string sourceRevision: ""
  property bool active: true
  property int fillMode: Image.PreserveAspectFit
  property int horizontalAlignment: Image.AlignHCenter
  property int verticalAlignment: Image.AlignVCenter
  property string animationIntent: "still"
  property bool mirror: false
  property bool mirrorVertically: false
  property bool paused: false
  property size sourceSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)), Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
  // Set when this image replaces a preferred one that could not be
  // displayed: the replacement renders, but the outcome is still a failure.
  property string replacementCode: ""
  property string replacementReason: ""

  readonly property int status: image.status
  readonly property string imageState: image.imageState
  readonly property bool failed: replacementCode !== "" || image.imageState === "unavailable"
  readonly property string errorCode: image.imageState === "unavailable" ? image.errorCode : replacementCode
  readonly property string errorReason: image.imageState === "unavailable" ? image.errorReason : replacementReason
  readonly property real paintedWidth: image.paintedWidth
  readonly property real paintedHeight: image.paintedHeight
  readonly property var imageResult: image.imageResult

  Accessible.role: Accessible.Graphic
  Accessible.description: failed ? errorReason : ""

  NImage {
    id: image
    anchors.fill: parent
    active: root.active && !!root.source
    source: root.source
    sourceRevision: root.sourceRevision
    sourceSize: root.sourceSize
    fillMode: root.fillMode
    horizontalAlignment: root.horizontalAlignment
    verticalAlignment: root.verticalAlignment
    animationIntent: root.animationIntent
    mirror: root.mirror
    mirrorVertically: root.mirrorVertically
    paused: root.paused
    smooth: root.smooth
    onImageStateChanged: {
      if (imageState === "unavailable")
        Qt.callLater(() => {
          if (image.imageState === "unavailable")
            Logger.w("NImageIcon", "Image could not be displayed:", image.errorCode);
        });
    }
  }

  AtmoIcon {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: root.failed
    icon: Icon.warning
    pointSize: Math.max(1, Math.min(Style.fontSizeM, root.width / 3))
    applyUiScale: false
    color: AtmoColor.mError
    Accessible.name: I18n.tr("widgets.file-picker.preview-unavailable")
    Accessible.description: root.errorReason
  }
}
