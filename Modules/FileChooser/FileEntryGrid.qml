import QtQuick
import QtQuick.Layouts
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
  property real iconSize: 96 * Style.uiScaleRatio
  property bool thumbnailActive: false
  property Component nameEditor: null
  readonly property var labelLines: FileLabels.lines(name, labelLane.width, text => labelMetrics.advanceWidth(text))
  readonly property var thumbnailState: artwork.thumbnailState
  function iconState() {
    return {
      artwork: artwork.metrics,
      label: {
        top: labelLane.y + gridLayout.y,
        artworkBottom: artwork.y + artwork.height + gridLayout.y,
        lines: labelLines,
        height: labelLane.height
      },
      thumbnailWidth: artwork.thumbnailWidth,
      thumbnailHeight: artwork.thumbnailHeight
    };
  }
  function artworkGeometry() {
    return artwork.mapToItem(root, 0, 0, artwork.width, artwork.height);
  }
  FontMetrics {
    id: labelMetrics
    font: labelTypography.font
  }
  NText {
    id: labelTypography
    visible: false
    pointSize: Style.fontSizeM
  }
  ColumnLayout {
    id: gridLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginXS
    FileEntryArtwork {
      id: artwork
      Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
      Layout.preferredWidth: root.iconSize
      Layout.preferredHeight: root.iconSize
      name: root.name
      path: root.path
      directory: root.directory
      modified: root.modified
      descriptor: root.descriptor
      thumbnailActive: root.thumbnailActive
    }
    Column {
      id: labelLane
      visible: root.nameEditor === null
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
    Loader {
      Layout.fillWidth: true
      visible: root.nameEditor !== null
      sourceComponent: root.nameEditor
    }
    Item {
      Layout.fillHeight: true
    }
  }
}
