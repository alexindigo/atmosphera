import QtQuick
import qs.Commons
import qs.Services.Files
import qs.Services.UI
import qs.Widgets

// One async artwork graph for grid, compact and details; off means no sources.
Item {
  id: root
  required property string name
  required property string path
  required property bool directory
  required property var modified
  required property var descriptor
  property var thumbnailProvider: null
  property bool thumbnailActive: false
  property bool compact: false
  readonly property var videoResult: videoThumbnail.item ? videoThumbnail.item.result : null
  readonly property bool previewUnavailable: thumbnail.imageState === "unavailable" || (!!videoResult && videoResult.status === "unavailable")
  readonly property string previewError: thumbnail.errorReason || (videoResult ? videoResult.reason || "" : "")
  readonly property string previewTooltip: errorHover.hovered && previewUnavailable ? I18n.tr("widgets.file-picker.preview-unavailable") + ": " + previewError : ""
  onPreviewTooltipChanged: {
    if (previewTooltip)
      TooltipService.show(root, previewTooltip);
    else
      TooltipService.hide(root);
  }
  opacity: descriptor.hidden ? .5 : 1
  layer.enabled: true
  readonly property var metrics: ({
                                    width: width,
                                    height: height,
                                    opacity: opacity,
                                    face: artwork.paints.face.toString()
                                  })
  readonly property var thumbnailState: ({
                                           path: path,
                                           active: thumbnailActive,
                                           ready: videoThumbnail.active && thumbnail.status === Image.Ready,
                                           imageReady: thumbnail.status === Image.Ready,
                                           unavailable: previewUnavailable,
                                           errorReason: previewError,
                                           state: thumbnail.imageState,
                                           source: String(thumbnail.source),
                                           opacity: opacity * thumbnailArtwork.opacity,
                                           reveal: thumbnailArtwork.opacity,
                                           fallbackOpacity: opacity * artwork.opacity,
                                           artworkOpacity: opacity,
                                           duration: Style.animationFast,
                                           playGeometry: {
                                             frameWidth: videoFrame.width,
                                             frameHeight: videoFrame.height,
                                             right: playBadge.x + playBadge.width,
                                             bottom: playBadge.y + playBadge.height
                                           }
                                         })
  readonly property real thumbnailWidth: thumbnail.width
  readonly property real thumbnailHeight: thumbnail.height
  Item {
    id: thumbnailArtwork
    anchors.fill: parent
    layer.enabled: true
    opacity: thumbnail.status === Image.Ready ? 1 : 0
    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationFast
      }
    }
    NImage {
      id: thumbnail
      anchors.fill: parent
      source: videoThumbnail.item ? videoThumbnail.item.url : (!root.directory && ["image", "animatedImage"].includes(FileTypes.previewKind(root.name)) ? root.path : "")
      active: root.thumbnailActive
      sourceRevision: String(root.modified)
      animationIntent: "still"
      thumbnail: !videoThumbnail.active
      sourceSize.width: Math.ceil(root.width * root.Screen.devicePixelRatio)
      sourceSize.height: Math.ceil(root.height * root.Screen.devicePixelRatio)
      asynchronous: true
      fillMode: Image.PreserveAspectFit
    }
    Item {
      id: videoFrame
      anchors.centerIn: thumbnail
      width: thumbnail.paintedWidth
      height: thumbnail.paintedHeight
      visible: videoThumbnail.active && thumbnail.status === Image.Ready
      Rectangle {
        id: playBadge
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(root.width / 3, Style.baseWidgetSize * .55)
        height: width
        radius: width / 2
        color: AtmoColor.mSurface
        AtmoIcon {
          anchors.centerIn: parent
          icon: Icon.mediaPlay
          pointSize: Math.min(Style.fontSizeS, parent.width / 2)
          color: AtmoColor.mOnSurface
        }
      }
    }
  }
  Loader {
    id: videoThumbnail
    active: root.thumbnailActive && !!root.thumbnailProvider && !root.directory && FileTypes.previewKind(root.name) === "video"
    sourceComponent: FileThumbnail {
      provider: root.thumbnailProvider
      path: root.path
      active: root.thumbnailActive
      pixels: Math.max(root.width, root.height) * root.Screen.devicePixelRatio
      stamp: String(root.modified)
    }
  }
  FileIcon {
    id: artwork
    anchors.fill: parent
    opacity: 1 - thumbnailArtwork.opacity
    compact: root.compact
    descriptor: root.descriptor
  }
  AtmoIcon {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: root.previewUnavailable
    icon: Icon.warning
    pointSize: Math.min(Style.fontSizeM, root.width / 3)
    color: AtmoColor.mError
    Accessible.name: I18n.tr("widgets.file-picker.preview-unavailable")
    Accessible.description: root.previewError
  }
  HoverHandler {
    id: errorHover
  }
}
