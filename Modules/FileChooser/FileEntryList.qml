import QtQuick
import qs.Commons
import qs.Services.Files
import qs.Widgets

FileListColumns {
  id: root
  required property string name
  required property bool directory
  required property double bytes
  required property var modified
  required property var descriptor
  property Component nameEditor: null
  function iconState() { return {artwork: leadingMetrics}; }
  leading: Component {
    Item {
      readonly property var metrics: ({width: artwork.width, height: artwork.height,
        opacity: artwork.opacity, face: artwork.paints.face.toString()})
      FileIcon {
        id: artwork
        anchors.centerIn: parent
        width: 20 * Style.uiScaleRatio
        height: width
        compact: true
        descriptor: root.descriptor
      }
    }
  }
  nameCell: root.nameEditor || normalName
  Component { id: normalName; NText { text: root.name; pointSize: Style.fontSizeM } }
  sizeCell: Component {
    NText {
      text: root.directory ? "" : FileTypes.formatSize(root.bytes)
      horizontalAlignment: Text.AlignRight
      pointSize: Style.fontSizeS
      features: ({tnum: 1})
      color: AtmoColor.mOnSurfaceVariant
    }
  }
  modifiedCell: Component {
    NText {
      text: FileTypes.formatDate(root.modified)
      pointSize: Style.fontSizeS
      features: ({tnum: 1})
      color: AtmoColor.mOnSurfaceVariant
    }
  }
}
