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
  property bool compactMode: false
  property real iconSize: (listMode || compactMode ? 20 : 96) * Style.uiScaleRatio
  property var columnWidths: []
  property bool selected: false
  property bool selectable: true
  property bool cursor: false
  property bool listingFocused: false
  property var thumbnailProvider: null
  property bool thumbnailActive: false
  property var operations: null
  readonly property bool renaming: !!operations && operations.renamePath === path
  readonly property var iconDescriptor: FileTypes.artwork(name, directory, path)
  readonly property var columnGeometry: listMode && visual.item ? visual.item.geometry : []
  readonly property var thumbnailState: visual.item ? visual.item.thumbnailState : ({})
  signal pressed(int modifiers)
  signal activated
  function focusEntry() {
    if (!renaming)
      forceActiveFocus(Qt.OtherFocusReason);
  }

  function iconState() {
    return visual.item ? Object.assign({
                                         name: name,
                                         descriptor: iconDescriptor,
                                         tileWidth: width,
                                         tileHeight: height
                                       }, visual.item.iconState()) : null;
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
  Accessible.description: (directory ? I18n.tr("widgets.file-picker.folder") : FileTypes.formatSize(bytes)) + (thumbnailState.unavailable ? "; " + I18n.tr("widgets.file-picker.preview-unavailable") + ": " + thumbnailState.errorReason : "")
  Accessible.focusable: true
  Accessible.selectable: selectable
  Accessible.selected: selected
  Accessible.onPressAction: pressed(Qt.NoModifier)
  Accessible.onToggleAction: pressed(Qt.ControlModifier)

  // A pooled row owns exactly one presentation graph, never hidden shapes,
  // image loaders, labels or column bindings for the other view.
  Loader {
    id: visual
    anchors.fill: parent
    asynchronous: true
    sourceComponent: root.listMode ? listVisual : root.compactMode ? compactVisual : gridVisual
  }
  Component {
    id: gridVisual
    FileEntryGrid {
      name: root.name
      path: root.path
      directory: root.directory
      modified: root.modified
      descriptor: root.iconDescriptor
      iconSize: root.iconSize
      thumbnailProvider: root.thumbnailProvider
      thumbnailActive: root.thumbnailActive
      nameEditor: root.renaming ? renameEditor : null
    }
  }
  Component {
    id: listVisual
    FileEntryList {
      name: root.name
      path: root.path
      directory: root.directory
      bytes: root.bytes
      modified: root.modified
      descriptor: root.iconDescriptor
      iconSize: root.iconSize
      widths: root.columnWidths
      thumbnailProvider: root.thumbnailProvider
      thumbnailActive: root.thumbnailActive
      nameEditor: root.renaming ? renameEditor : null
    }
  }
  Component {
    id: compactVisual
    FileEntryCompact {
      name: root.name
      path: root.path
      directory: root.directory
      modified: root.modified
      descriptor: root.iconDescriptor
      iconSize: root.iconSize
      thumbnailProvider: root.thumbnailProvider
      thumbnailActive: root.thumbnailActive
      nameEditor: root.renaming ? renameEditor : null
    }
  }
  Component {
    id: renameEditor
    ChooserTextField {
      accessibleName: I18n.tr("widgets.file-picker.rename-name")
      text: root.operations.renameName
      readOnly: root.operations.busy
      onTextEdited: root.operations.renameName = text
      onAccepted: root.operations.rename(text)
      Component.onCompleted: Qt.callLater(function () {
        inputItem.forceActiveFocus();
        var dot = root.directory ? -1 : text.lastIndexOf(".");
        inputItem.select(0, dot > 0 ? dot : text.length);
      })
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }
  ToolTip.visible: pointer.containsMouse
  ToolTip.text: root.name
  ToolTip.delay: 700
}
