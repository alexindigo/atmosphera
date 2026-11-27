import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root
  required property string name
  required property string path
  required property bool directory
  required property var modified
  required property var descriptor
  required property real iconSize
  property bool thumbnailActive: false
  property Component nameEditor: null
  readonly property var thumbnailState: artwork.thumbnailState
  function iconState() {
    return {
      artwork: artwork.metrics
    };
  }
  function artworkGeometry() {
    return artwork.mapToItem(root, 0, 0, artwork.width, artwork.height);
  }
  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.marginXS
    spacing: Style.marginM
    FileEntryArtwork {
      id: artwork
      Layout.preferredWidth: root.iconSize
      Layout.preferredHeight: root.iconSize
      name: root.name
      path: root.path
      directory: root.directory
      modified: root.modified
      descriptor: root.descriptor
      compact: true
      thumbnailActive: root.thumbnailActive
    }
    NText {
      Layout.fillWidth: true
      visible: root.nameEditor === null
      text: root.name
      pointSize: Style.fontSizeM
      elide: Text.ElideRight
    }
    Loader {
      Layout.fillWidth: true
      visible: root.nameEditor !== null
      sourceComponent: root.nameEditor
    }
  }
}
