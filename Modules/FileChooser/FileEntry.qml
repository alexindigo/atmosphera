import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets
import "../../Helpers/PortalPaths.js" as PortalPaths

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
  signal pressed(int modifiers)
  signal activated
  readonly property var columnGeometry: listColumns.geometry
  color: selected ? Qt.alpha(AtmoColor.mPrimary, 0.18) : (pointer.containsMouse ? Qt.alpha(AtmoColor.mOnSurface, 0.05) : "transparent")
  radius: Style.iRadiusS
  border.width: cursor && listingFocused ? Style.borderM : 0
  border.color: AtmoColor.mPrimary
  Accessible.role: Accessible.ListItem
  Accessible.name: name
  Accessible.selected: selected

  GridLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM
    visible: !root.listMode
    columns: 1
    rowSpacing: Style.marginXS
    columnSpacing: Style.marginM
    Item {
      Layout.preferredWidth: root.listMode ? 26 * Style.uiScaleRatio : -1
      Layout.fillWidth: !root.listMode
      Layout.fillHeight: !root.listMode
      Layout.preferredHeight: root.listMode ? 26 * Style.uiScaleRatio : 80 * Style.uiScaleRatio
      Image {
        id: thumbnail
        anchors.fill: parent
        source: !root.directory && !root.listMode && ["image", "animatedImage"].includes(FileTypes.previewKind(root.name)) ? PortalPaths.pathToUri(root.path).uri : ""
        sourceSize.width: 160
        sourceSize.height: 120
        asynchronous: true
        fillMode: Image.PreserveAspectFit
      }
      AtmoIcon {
        anchors.centerIn: parent
        visible: thumbnail.status !== Image.Ready
        icon: FileTypes.icon(root.name, root.directory)
        pointSize: root.listMode ? Style.fontSizeL : Style.fontSizeXXXL * 1.6
        color: root.directory ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
      }
    }
    NText {
      Layout.fillWidth: true
      Layout.preferredWidth: root.listMode ? 1 : -1
      text: root.name
      horizontalAlignment: root.listMode ? Text.AlignLeft : Text.AlignHCenter
      pointSize: Style.fontSizeM
      maximumLineCount: root.listMode ? 1 : 2
      wrapMode: root.listMode ? Text.NoWrap : Text.WrapAnywhere
      Layout.preferredHeight: root.listMode ? -1 : 38 * Style.uiScaleRatio
    }
    NText {
      visible: root.listMode
      Layout.preferredWidth: 92 * Style.uiScaleRatio
      horizontalAlignment: Text.AlignRight
      text: root.directory ? "" : FileTypes.formatSize(root.bytes)
      pointSize: Style.fontSizeS
      features: ({tnum: 1})
      color: AtmoColor.mOnSurfaceVariant
    }
    NText {
      visible: root.listMode
      Layout.preferredWidth: 164 * Style.uiScaleRatio
      text: FileTypes.formatDate(root.modified)
      pointSize: Style.fontSizeS
      features: ({tnum: 1})
      color: AtmoColor.mOnSurfaceVariant
    }
  }
  FileListColumns {
    id: listColumns
    anchors.fill: parent
    visible: root.listMode
    leading: Component { AtmoIcon { icon: FileTypes.icon(root.name, root.directory); pointSize: Style.fontSizeL; color: root.directory ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant } }
    nameCell: Component { NText { text: root.name; pointSize: Style.fontSizeM } }
    sizeCell: Component { NText { text: root.directory ? "" : FileTypes.formatSize(root.bytes); horizontalAlignment: Text.AlignRight; pointSize: Style.fontSizeS; features: ({tnum: 1}); color: AtmoColor.mOnSurfaceVariant } }
    modifiedCell: Component { NText { text: FileTypes.formatDate(root.modified); pointSize: Style.fontSizeS; features: ({tnum: 1}); color: AtmoColor.mOnSurfaceVariant } }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    onClicked: mouse => root.pressed(mouse.modifiers)
    onDoubleClicked: root.activated()
  }
}
