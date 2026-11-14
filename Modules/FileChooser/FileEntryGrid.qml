import QtQuick
import QtQuick.Layouts
import "../../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons
import qs.Services.Files
import qs.Widgets

Item {
  id: root
  required property string name
  required property string path
  required property bool directory
  required property var modified
  required property var descriptor
  property var thumbnailProvider: null
  property bool thumbnailActive: false
  readonly property var labelLines: FileLabels.lines(name, labelLane.width, text => labelMetrics.advanceWidth(text))
  readonly property var thumbnailState: ({
    path: path, active: thumbnailActive,
    ready: videoThumbnail.active && thumbnail.status === Image.Ready,
    imageReady: thumbnail.status === Image.Ready, source: String(thumbnail.source),
    opacity: artwork.opacity * thumbnailArtwork.opacity, reveal: thumbnailArtwork.opacity,
    fallbackOpacity: artwork.opacity * gridIcon.opacity, artworkOpacity: artwork.opacity,
    duration: Style.animationFast,
    playGeometry: {frameWidth: videoFrame.width, frameHeight: videoFrame.height,
      right: playBadge.x + playBadge.width, bottom: playBadge.y + playBadge.height}
  })
  function iconState() {
    return {
      artwork: {width: artwork.width, height: artwork.height, opacity: artwork.opacity, face: gridIcon.paints.face.toString()},
      label: {top: labelLane.y + gridLayout.y, artworkBottom: artwork.y + artwork.height + gridLayout.y,
        lines: labelLines, height: labelLane.height},
      thumbnailWidth: thumbnail.width, thumbnailHeight: thumbnail.height
    };
  }
  function artworkGeometry() { return artwork.mapToItem(root, 0, 0, artwork.width, artwork.height); }
  FontMetrics { id: labelMetrics; font: labelTypography.font }
  NText { id: labelTypography; visible: false; pointSize: Style.fontSizeM }
  ColumnLayout {
    id: gridLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginXS
    Item {
      id: artwork
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.preferredWidth: 96 * Style.uiScaleRatio
      Layout.preferredHeight: 96 * Style.uiScaleRatio
      layer.enabled: true
      opacity: root.descriptor.hidden ? .5 : 1
      Item {
        id: thumbnailArtwork
        anchors.fill: parent
        layer.enabled: true
        opacity: thumbnail.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.animationFast } }
        Image {
          id: thumbnail
          anchors.fill: parent
          source: videoThumbnail.item ? videoThumbnail.item.url : (!root.directory && ["image", "animatedImage"].includes(FileTypes.previewKind(root.name)) ? PortalPaths.pathToUri(root.path).uri : "")
          sourceSize.width: Math.ceil(artwork.width * root.Screen.devicePixelRatio)
          sourceSize.height: Math.ceil(artwork.height * root.Screen.devicePixelRatio)
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
            width: Style.baseWidgetSize * .55
            height: width
            radius: width / 2
            color: AtmoColor.mSurface
            AtmoIcon {
              anchors.centerIn: parent
              icon: Icon.mediaPlay
              pointSize: Style.fontSizeS
              color: AtmoColor.mOnSurface
            }
          }
        }
      }
      Loader {
        id: videoThumbnail
        active: !!root.thumbnailProvider && !root.directory && FileTypes.previewKind(root.name) === "video"
        sourceComponent: FileThumbnail {
          provider: root.thumbnailProvider
          path: root.path
          active: root.thumbnailActive
          pixels: Math.max(root.width, root.height) * root.Screen.devicePixelRatio
          stamp: String(root.modified)
        }
      }
      FileIcon {
        id: gridIcon
        anchors.centerIn: parent
        width: artwork.width
        height: artwork.height
        opacity: 1 - thumbnailArtwork.opacity
        descriptor: root.descriptor
      }
    }
    Column {
      id: labelLane
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      Layout.preferredHeight: labelTypography.implicitHeight * 2
      Repeater {
        model: root.labelLines
        NText {
          required property string modelData
          width: labelLane.width
          text: modelData
          font: labelTypography.font
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignTop
          elide: Text.ElideRight
        }
      }
    }
    Item { Layout.fillHeight: true }
  }
}
