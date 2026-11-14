import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Services.Files

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
  readonly property var columnGeometry: listMode && visual.item ? visual.item.geometry : []
  readonly property var thumbnailState: !listMode && visual.item ? visual.item.thumbnailState : ({})
  signal pressed(int modifiers)
  signal activated

  function iconState() {
    return visual.item ? Object.assign({name: name, descriptor: iconDescriptor, tileWidth: width, tileHeight: height}, visual.item.iconState()) : null;
  }
  function artworkGeometry() {
    if (!visual.item || listMode)
      return Qt.rect(0, 0, width, height);
    var r = visual.item.artworkGeometry();
    return visual.item.mapToItem(root, r.x, r.y, r.width, r.height);
  }
  color: selected ? Qt.alpha(AtmoColor.mPrimary, 0.18) : (pointer.containsMouse ? Qt.alpha(AtmoColor.mOnSurface, 0.05) : "transparent")
  radius: Style.iRadiusS
  border.width: cursor && listingFocused ? Style.borderM : 0
  border.color: AtmoColor.mPrimary
  Accessible.role: Accessible.ListItem
  Accessible.name: name
  Accessible.selected: selected

  // A pooled row owns exactly one presentation graph, never hidden shapes,
  // image loaders, labels or column bindings for the other view.
  Loader {
    id: visual
    anchors.fill: parent
    asynchronous: true
    sourceComponent: root.listMode ? listVisual : gridVisual
  }
  Component {
    id: gridVisual
    FileEntryGrid {
      name: root.name
      path: root.path
      directory: root.directory
      modified: root.modified
      descriptor: root.iconDescriptor
      thumbnailProvider: root.thumbnailProvider
      thumbnailActive: root.thumbnailActive
    }
  }
  Component {
    id: listVisual
    FileEntryList {
      name: root.name
      directory: root.directory
      bytes: root.bytes
      modified: root.modified
      descriptor: root.iconDescriptor
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    onClicked: mouse => root.pressed(mouse.modifiers)
    onDoubleClicked: root.activated()
  }
  ToolTip.visible: pointer.containsMouse
  ToolTip.text: root.name
  ToolTip.delay: 700
}
