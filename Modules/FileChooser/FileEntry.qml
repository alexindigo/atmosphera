import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../Helpers/PortalPaths.js" as PortalPaths
import qs.Commons
import qs.Services.Files
import qs.Widgets

Rectangle {
  id: root
  required property string name
  required property string path
  required property bool directory
  required property double bytes
  required property var modified
  property bool listMode: false
  property bool selected: false
  property bool cursor: false
  property bool listingFocused: false
  property var thumbnailProvider: null
  property bool thumbnailActive: false
  readonly property var iconDescriptor: FileTypes.artwork(name, directory, path)
  readonly property var labelLines: FileLabels.lines(name, labelLane.width, text => labelMetrics.advanceWidth(text))
  readonly property var labelGeometry: ({top: labelLane.y + gridLayout.y, artworkBottom: artwork.y + artwork.height + gridLayout.y, lines: labelLines, height: labelLane.height})
  FontMetrics { id: labelMetrics; font: labelTypography.font }
  NText { id: labelTypography; visible: false; pointSize: Style.fontSizeM }
  readonly property var iconState: ({
                                      name: name,
                                      descriptor: iconDescriptor,
                                      artwork: listMode ? listColumns.leadingMetrics : {
                                                            width: artwork.width,
                                                            height: artwork.height,
                                                            opacity: artwork.opacity,
                                                            face: gridIcon.paints.face.toString()
                                                          },
                                      tileWidth: width,
                                      tileHeight: height,
                                      label: labelGeometry,
                                      thumbnailWidth: thumbnail.width,
                                      thumbnailHeight: thumbnail.height
                                    })
  function artworkGeometry() {
    return artwork.mapToItem(root, 0, 0, artwork.width, artwork.height);
  }
  signal pressed(int modifiers)
  signal activated
  readonly property var columnGeometry: listColumns.geometry
  readonly property var thumbnailState: ({
                                           path: path,
                                           active: thumbnailActive,
                                           ready: videoThumbnail.active && thumbnail.status === Image.Ready,
                                           imageReady: thumbnail.status === Image.Ready,
                                           source: String(thumbnail.source),
                                           opacity: artwork.opacity * thumbnailArtwork.opacity,
                                           reveal: thumbnailArtwork.opacity,
                                           fallbackOpacity: artwork.opacity * gridIcon.opacity,
                                           artworkOpacity: artwork.opacity,
                                           duration: Style.animationFast,
                                           playGeometry: {
                                             frameWidth: videoFrame.width,
                                             frameHeight: videoFrame.height,
                                             right: playBadge.x + playBadge.width,
                                             bottom: playBadge.y + playBadge.height
                                           }
                                         })
  color: selected ? Qt.alpha(AtmoColor.mPrimary, 0.18) : (pointer.containsMouse ? Qt.alpha(AtmoColor.mOnSurface, 0.05) : "transparent")
  radius: Style.iRadiusS
  border.width: cursor && listingFocused ? Style.borderM : 0
  border.color: AtmoColor.mPrimary
  Accessible.role: Accessible.ListItem
  Accessible.name: name
  Accessible.selected: selected

  ColumnLayout {
    id: gridLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    visible: !root.listMode
    spacing: Style.marginXS
    Item {
      id: artwork
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.preferredWidth: 96 * Style.uiScaleRatio
      Layout.preferredHeight: 96 * Style.uiScaleRatio
      // Hidden alpha is applied after the complete icon/thumbnail handoff.
      layer.enabled: true
      opacity: root.iconDescriptor.hidden ? .5 : 1
      Item {
        id: thumbnailArtwork
        anchors.fill: parent
        // One reveal animates the finished image plus its play badge. The
        // fallback binds to the same value's complement, including hidden tiles.
        layer.enabled: true
        opacity: thumbnail.status === Image.Ready ? 1 : 0
        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
          }
        }
        Image {
          id: thumbnail
          anchors.fill: parent
          source: videoThumbnail.item ? videoThumbnail.item.url : (!root.directory && !root.listMode && ["image", "animatedImage"].includes(FileTypes.previewKind(root.name)) ? PortalPaths.pathToUri(root.path).uri : "")
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
        active: !!root.thumbnailProvider && !root.directory && !root.listMode && FileTypes.previewKind(root.name) === "video"
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
        descriptor: root.iconDescriptor
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
    NText {
      visible: root.listMode
      Layout.preferredWidth: 92 * Style.uiScaleRatio
      horizontalAlignment: Text.AlignRight
      text: root.directory ? "" : FileTypes.formatSize(root.bytes)
      pointSize: Style.fontSizeS
      features: ({
                   tnum: 1
                 })
      color: AtmoColor.mOnSurfaceVariant
    }
    NText {
      visible: root.listMode
      Layout.preferredWidth: 164 * Style.uiScaleRatio
      text: FileTypes.formatDate(root.modified)
      pointSize: Style.fontSizeS
      features: ({
                   tnum: 1
                 })
      color: AtmoColor.mOnSurfaceVariant
    }
  }
  FileListColumns {
    id: listColumns
    anchors.fill: parent
    visible: root.listMode
    leading: Component {
      Item {
        readonly property var metrics: ({
                                          width: compactIcon.width,
                                          height: compactIcon.height,
                                          opacity: compactIcon.opacity,
                                          face: compactIcon.paints.face.toString()
                                        })
        FileIcon {
          id: compactIcon
          anchors.centerIn: parent
          width: 20 * Style.uiScaleRatio
          height: width
          compact: true
          descriptor: root.iconDescriptor
        }
      }
    }
    nameCell: Component {
      NText {
        text: root.name
        pointSize: Style.fontSizeM
      }
    }
    sizeCell: Component {
      NText {
        text: root.directory ? "" : FileTypes.formatSize(root.bytes)
        horizontalAlignment: Text.AlignRight
        pointSize: Style.fontSizeS
        features: ({
                     tnum: 1
                   })
        color: AtmoColor.mOnSurfaceVariant
      }
    }
    modifiedCell: Component {
      NText {
        text: FileTypes.formatDate(root.modified)
        pointSize: Style.fontSizeS
        features: ({
                     tnum: 1
                   })
        color: AtmoColor.mOnSurfaceVariant
      }
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    onClicked: mouse => root.pressed(mouse.modifiers)
    onDoubleClicked: root.activated()
  }
  // The complete filename remains available even when either fixed line elides.
  ToolTip.visible: pointer.containsMouse
  ToolTip.text: root.name
  ToolTip.delay: 700
}
