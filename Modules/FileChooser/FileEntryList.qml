import QtQuick
import qs.Commons
import qs.Services.Files
import qs.Widgets

FileListColumns {
  id: root
  required property string name
  required property string path
  required property bool directory
  required property double bytes
  required property var modified
  required property var descriptor
  property real iconSize: 20 * Style.uiScaleRatio
  property var thumbnailProvider: null
  property bool thumbnailActive: false
  property Component nameEditor: null
  leadingWidth: iconSize + Style.marginXS
  readonly property var thumbnailState: leadingThumbnailState
  function iconState() {
    return {
      artwork: leadingMetrics
    };
  }
  leading: Component {
    Item {
      readonly property var metrics: artwork.metrics
      readonly property var thumbnailState: artwork.thumbnailState
      // The slot owns sizing; the artwork itself stays square and centered.
      FileEntryArtwork {
        id: artwork
        anchors.centerIn: parent
        width: root.iconSize
        height: width
        compact: true
        name: root.name
        path: root.path
        directory: root.directory
        modified: root.modified
        descriptor: root.descriptor
        thumbnailProvider: root.thumbnailProvider
        thumbnailActive: root.thumbnailActive
      }
    }
  }
  nameCell: root.nameEditor || normalName
  Component {
    id: normalName
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
