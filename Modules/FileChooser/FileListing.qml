import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

FocusScope {
  id: root
  required property var request
  readonly property bool navigationFocused: !!root.Window.window && root.Window.window.activeFocusItem === root
  readonly property int columns: Math.max(1, Math.floor(grid.width / (144 * Style.uiScaleRatio)))
  readonly property var cursorItem: {
    void request.browser.count;
    return request.browser.entry(request.selection.cursor);
  }
  readonly property var columnGeometry: ({header: listHeaders.geometry, row: list.itemAtIndex(0) ? list.itemAtIndex(0).columnGeometry : []})
  signal quickLookRequested(rect tile)
  signal editPathRequested(string initial)
  activeFocusOnTab: true

  function tileRect() {
    var view = request.viewMode === "list" ? list : grid;
    var tile = view.itemAtIndex(request.selection.cursor);
    return tile ? tile.mapToItem(root, 0, 0, tile.width, tile.height) : Qt.rect(0, 0, root.width, root.height);
  }
  function sort(key) {
    request.browser.sortDescending = request.browser.sortKey === key ? !request.browser.sortDescending : false;
    request.browser.sortKey = key;
  }
  Keys.onPressed: event => {
    if (!navigationFocused) {
      event.accepted = false;
      return;
    }
    var shift = !!(event.modifiers & Qt.ShiftModifier);
    var alt = !!(event.modifiers & Qt.AltModifier);
    var ctrl = !!(event.modifiers & Qt.ControlModifier);
    event.accepted = true;
    if (alt && event.key === Qt.Key_Left) request.browser.back();
    else if (alt && event.key === Qt.Key_Right) request.browser.forward();
    else if (event.key === Qt.Key_Backspace || (alt && event.key === Qt.Key_Up)) request.browser.up();
    else if (ctrl && event.key === Qt.Key_A) request.selection.selectAll();
    else if (ctrl && event.key === Qt.Key_H) request.browser.showHidden = !request.browser.showHidden;
    else if (event.key === Qt.Key_Left) request.selection.move(-1, shift);
    else if (event.key === Qt.Key_Right) request.selection.move(1, shift);
    else if (event.key === Qt.Key_Up) request.selection.move(request.viewMode === "grid" ? -columns : -1, shift);
    else if (event.key === Qt.Key_Down) request.selection.move(request.viewMode === "grid" ? columns : 1, shift);
    else if (event.key === Qt.Key_Home) request.selection.click(0, shift ? Qt.ShiftModifier : Qt.NoModifier);
    else if (event.key === Qt.Key_End) request.selection.click(request.browser.count - 1, shift ? Qt.ShiftModifier : Qt.NoModifier);
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) request.activate(request.selection.cursor);
    else if (event.key === Qt.Key_Space && cursorItem) quickLookRequested(tileRect());
    else if (event.text === "/" || event.text === "~") editPathRequested(event.text);
    else if (!ctrl && !alt && event.text.length && event.text >= " ") request.selection.typeAhead(event.text);
    else event.accepted = false;
  }

  Rectangle { anchors.fill: parent; color: "transparent"; border.width: root.navigationFocused ? Style.borderS : 0; border.color: AtmoColor.mOutline; radius: Style.iRadiusS }
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginXS
    spacing: Style.marginXS
    FileListColumns {
      id: listHeaders
      visible: root.request.viewMode === "list"
      Layout.fillWidth: true
      Layout.rightMargin: Style.marginL
      Layout.preferredHeight: 54 * Style.uiScaleRatio
      nameCell: Component { FileColumnHeader { text: I18n.tr("widgets.file-picker.name") + (root.request.browser.sortKey === "name" ? (root.request.browser.sortDescending ? " ↓" : " ↑") : ""); onClicked: root.sort("name") } }
      sizeCell: Component { FileColumnHeader { alignment: Text.AlignRight; text: I18n.tr("widgets.file-picker.size") + (root.request.browser.sortKey === "size" ? (root.request.browser.sortDescending ? " ↓" : " ↑") : ""); onClicked: root.sort("size") } }
      modifiedCell: Component { FileColumnHeader { text: I18n.tr("widgets.file-picker.modified") + (root.request.browser.sortKey === "modified" ? (root.request.browser.sortDescending ? " ↓" : " ↑") : ""); onClicked: root.sort("modified") } }
    }
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      GridView {
        id: grid
        anchors.fill: parent
        anchors.rightMargin: Style.marginL
        visible: root.request.viewMode !== "list"
        clip: true
        model: root.request.browser.model
        cellWidth: width / root.columns
        cellHeight: 144 * Style.uiScaleRatio
        currentIndex: root.request.selection.cursor
        keyNavigationEnabled: false
        highlightMoveDuration: 0
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
        ScrollBar.vertical: ScrollBar {}
        delegate: FileEntry {
          required property int index
          required property string fileName
          required property string filePath
          required property bool fileIsDir
          required property double fileSize
          required property var fileModified
          width: grid.cellWidth - Style.marginXS
          height: grid.cellHeight - Style.marginXS
          name: fileName; path: filePath; directory: fileIsDir; bytes: fileSize; modified: fileModified
          selected: root.request.selection.selectedPaths.includes(filePath)
          cursor: root.request.selection.cursor === index
          listingFocused: root.navigationFocused
          onPressed: modifiers => { root.forceActiveFocus(); root.request.selection.click(index, modifiers); }
          onActivated: root.request.activate(index)
        }
      }
      ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: Style.marginL
        visible: root.request.viewMode === "list"
        clip: true
        model: root.request.browser.model
        currentIndex: root.request.selection.cursor
        keyNavigationEnabled: false
        highlightMoveDuration: 0
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        ScrollBar.vertical: ScrollBar {}
        delegate: FileEntry {
          required property int index
          required property string fileName
          required property string filePath
          required property bool fileIsDir
          required property double fileSize
          required property var fileModified
          width: list.width
          height: 48 * Style.uiScaleRatio
          name: fileName; path: filePath; directory: fileIsDir; bytes: fileSize; modified: fileModified
          listMode: true
          selected: root.request.selection.selectedPaths.includes(filePath)
          cursor: root.request.selection.cursor === index
          listingFocused: root.navigationFocused
          onPressed: modifiers => { root.forceActiveFocus(); root.request.selection.click(index, modifiers); }
          onActivated: root.request.activate(index)
        }
      }
      ColumnLayout {
        anchors.centerIn: parent
        visible: root.request.browser.count === 0 && root.request.browser.status !== "loading"
        spacing: Style.marginL
        AtmoIcon { Layout.alignment: Qt.AlignHCenter; icon: Icon.filepickerFolder; pointSize: Style.fontSizeXXXL * 2; color: AtmoColor.mOnSurfaceVariant }
        NText { Layout.alignment: Qt.AlignHCenter; text: I18n.tr("widgets.file-picker.empty-folder"); pointSize: Style.fontSizeL }
        ChooserButton { Layout.alignment: Qt.AlignHCenter; visible: root.request.browser.hasHidden && !root.request.browser.showHidden; text: I18n.tr("widgets.file-picker.show-hidden"); onClicked: root.request.browser.showHidden = true }
      }
      BusyIndicator { anchors.centerIn: parent; visible: root.request.browser.status === "loading"; running: visible }
    }
  }
}
