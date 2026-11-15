import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

Rectangle {
  id: root
  required property var browser
  color: AtmoColor.mSurfaceVariant
  implicitWidth: 190 * Style.uiScaleRatio
  readonly property bool menuOpen: favoriteMenu.visible
  property string pendingVolume: ""
  property string _focusPath: ""
  property string _focusNeighbor: ""
  property bool _focusPending: false
  property bool _volumeAction: false
  signal listingFocusRequested()
  function prepareFocus(path) {
    _focusPath = path;
    var index = FilePlaces.favorites.findIndex(entry => entry.path === path);
    _focusNeighbor = (FilePlaces.favorites[index + 1] || FilePlaces.favorites[index - 1] || {}).path || "";
    _focusPending = true;
  }
  function restorePlaceFocus() {
    if (!_focusPending || FilePlaces.loading || favoriteMenu.visible) return;
    var target = null;
    for (var path of [_focusPath, _focusNeighbor]) {
      for (var i = 0; i < favoriteRepeater.count && !target; i++) {
        var item = favoriteRepeater.itemAt(i);
        if (item && item.modelData.path === path) target = item;
      }
    }
    if (!target) target = addFavorite.visible ? addFavorite : standardRepeater.itemAt(0);
    _focusPending = false;
    if (!target) return;
    // ScrollView's public Flickable surface keeps the returned target visible,
    // including when reordering across the edge of a long favorites list.
    var view = placeScroll.contentItem;
    if (view && view.contentY !== undefined) {
      var p = target.mapToItem(view, 0, 0);
      if (p.y < 0) view.contentY += p.y;
      else if (p.y + target.height > view.height) view.contentY += p.y + target.height - view.height;
    }
    target.forceActiveFocus();
  }
  function dismissMenu() { favoriteMenu.close(); }
  function state(target) {
    var rows = [];
    for (var repeater of [standardRepeater, favoriteRepeater, volumeRepeater]) {
      for (var i = 0; i < repeater.count; i++) {
        var item = repeater.itemAt(i), r = item.mapToItem(target, 0, 0, item.width, item.height);
        rows.push(Object.assign({name: item.modelData.name, path: item.modelData.path, id: item.modelData.id || "", kind: item.modelData.kind,
          x: r.x, y: r.y, width: r.width, height: r.height}, typeof item.geometry === "function" ? item.geometry(target) : {}));
      }
    }
    return {favorites: FilePlaces.favorites, busy: FilePlaces.editing || FileVolumes.busy, rows: rows, menu: favoriteMenu.state(target)};
  }
  function editFavorite(item, entry, index) {
    prepareFocus(entry.path);
    favoriteMenu.entries = [{key: "remove", name: I18n.tr("widgets.file-picker.remove-favorite"), path: entry.path}]
      .concat(index > 0 ? [{key: "up", name: I18n.tr("widgets.file-picker.move-up"), path: entry.path}] : [])
      .concat(index < FilePlaces.favorites.length - 1 ? [{key: "down", name: I18n.tr("widgets.file-picker.move-down"), path: entry.path}] : []);
    var p = item.mapToItem(root, 0, item.height);
    favoriteMenu.x = p.x; favoriteMenu.y = Math.min(p.y, root.height - favoriteMenu.implicitHeight);
    favoriteMenu.open();
  }
  ChooserMenu {
    id: favoriteMenu
    title: I18n.tr("widgets.file-picker.favorites")
    onClosed: Qt.callLater(root.restorePlaceFocus)
    onTriggered: entry => {
      if (entry.key === "remove") FilePlaces.removeFavorite(entry.path);
      else FilePlaces.moveFavorite(entry.path, entry.key === "up" ? -1 : 1);
    }
  }
  Connections {
    target: FilePlaces
    function onRefreshed() { Qt.callLater(root.restorePlaceFocus); }
  }
  Connections {
    target: FileVolumes
    function onMounted(id, path) {
      if (root.pendingVolume === id) { root.pendingVolume = ""; root.browser.navigate(path); root.listingFocusRequested(); }
    }
    function onBusyChanged() {
      if (FileVolumes.busy) return;
      if (root._volumeAction || (root.pendingVolume && FileVolumes.errorText)) root.listingFocusRequested();
      root._volumeAction = false;
      if (FileVolumes.errorText) root.pendingVolume = "";
    }
  }
  Connections {
    target: root.browser
    function onNavigationRequested() { root.pendingVolume = ""; }
  }
  function recentRows() {
    var rows = [];
    for (var i = 0; i < recentRepeater.count; i++) {
      var item = recentRepeater.itemAt(i);
      if (item)
        rows.push({name: item.text, path: item.tooltipText});
    }
    return rows;
  }

  ScrollView {
    id: placeScroll
    anchors.fill: parent
    anchors.margins: Style.marginM
    contentWidth: availableWidth
    clip: true
    ScrollBar.vertical: ScrollBar { Accessible.name: I18n.tr("widgets.file-picker.scroll-places") }
    ScrollBar.horizontal: ScrollBar { Accessible.name: I18n.tr("widgets.file-picker.scroll-places") }
    ColumnLayout {
      width: parent.width
      spacing: Style.marginXS
      Repeater {
        id: standardRepeater
        model: FilePlaces.places.filter(entry => entry.kind !== "bookmark")
        FilePlaceButton {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.name
          icon: modelData.kind === "home" ? Icon.filepickerHome : Icon.filepickerFolder
          selected: root.browser.currentPath === modelData.path
          onClicked: root.browser.navigate(modelData.path)
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        NText { Layout.fillWidth: true; text: I18n.tr("widgets.file-picker.favorites"); pointSize: Style.fontSizeS; Layout.leftMargin: Style.marginM; elide: Text.ElideRight }
        ChooserButton {
          id: addFavorite
          icon: Icon.add
          tooltipText: I18n.tr("widgets.file-picker.add-favorite")
          visible: root.browser.currentPath !== "" && !FilePlaces.isFavorite(root.browser.currentPath) && !FilePlaces.editing
          onClicked: { root.prepareFocus(root.browser.currentPath); FilePlaces.addFavorite(root.browser.currentPath); }
        }
      }
      Repeater {
        id: favoriteRepeater
        model: FilePlaces.favorites
        FilePlaceButton {
          id: favorite
          required property var modelData
          required property int index
          Layout.fillWidth: true
          text: modelData.name
          tooltipText: modelData.path
          selected: root.browser.currentPath === modelData.path
          onClicked: root.browser.navigate(modelData.path)
          onContextRequested: if (!FilePlaces.editing) root.editFavorite(favorite, modelData, index)
        }
      }
      NText {
        Layout.fillWidth: true
        visible: FilePlaces.errorText !== ""
        text: FilePlaces.errorText
        color: AtmoColor.mError
        wrapMode: Text.Wrap
        pointSize: Style.fontSizeS
      }
      Rectangle { visible: FilePlaces.recentFolders.length > 0 || FilePlaces.removable.length > 0; Layout.fillWidth: true; Layout.topMargin: Style.marginM; Layout.bottomMargin: Style.marginM; implicitHeight: Style.borderS; color: AtmoColor.mOutline }
      NText { visible: FilePlaces.recentFolders.length > 0; text: I18n.tr("widgets.file-picker.recent"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM }
      Repeater {
        id: recentRepeater
        model: FilePlaces.recentFolders
        FilePlaceButton {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.name
          icon: Icon.filepickerFolder
          tooltipText: modelData.path
          selected: root.browser.currentPath === modelData.path
          onClicked: root.browser.navigate(modelData.path)
        }
      }
      NText { visible: FilePlaces.removable.length > 0; text: I18n.tr("widgets.file-picker.volumes"); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant; Layout.leftMargin: Style.marginM; Layout.topMargin: Style.marginL }
      Repeater {
        id: volumeRepeater
        model: FilePlaces.removable
        RowLayout {
          id: volumeRow
          required property var modelData
          Layout.fillWidth: true
          spacing: 0
          function geometry(target) {
            function rect(item) {
              var r = item.mapToItem(target, 0, 0, item.width, item.height);
              return {x: r.x, y: r.y, width: r.width, height: r.height, visible: item.visible};
            }
            return {mount: rect(volumePlace), action: rect(volumeAction)};
          }
          FilePlaceButton {
            id: volumePlace
            Layout.fillWidth: true
            text: volumeRow.modelData.name
            tooltipText: volumeRow.modelData.mounted ? volumeRow.modelData.path : I18n.tr("widgets.file-picker.mount")
            selected: volumeRow.modelData.path !== "" && root.browser.currentPath === volumeRow.modelData.path
            visible: !FileVolumes.busy
            onClicked: {
              if (volumeRow.modelData.mounted) root.browser.navigate(volumeRow.modelData.path);
              else { root.pendingVolume = volumeRow.modelData.id; FileVolumes.mount(volumeRow.modelData.id); }
            }
          }
          NText {
            Layout.fillWidth: true
            visible: FileVolumes.busy
            text: volumeRow.modelData.name
            elide: Text.ElideRight
          }
          ChooserButton {
            id: volumeAction
            visible: !FileVolumes.busy && (volumeRow.modelData.mounted || volumeRow.modelData.ejectable)
            icon: Icon.filepickerEject
            tooltipText: I18n.tr(volumeRow.modelData.ejectable ? "widgets.file-picker.eject" : "widgets.file-picker.unmount") + " " + volumeRow.modelData.name
            onClicked: {
              root._volumeAction = true;
              if (volumeRow.modelData.ejectable) FileVolumes.eject(volumeRow.modelData.id);
              else FileVolumes.unmount(volumeRow.modelData.id);
              if (!FileVolumes.busy) { root._volumeAction = false; root.listingFocusRequested(); }
            }
          }
        }
      }
      NText {
        Layout.fillWidth: true
        visible: FileVolumes.busy || FileVolumes.errorText !== ""
        text: FileVolumes.errorText || I18n.tr("common.loading")
        color: FileVolumes.errorText ? AtmoColor.mError : AtmoColor.mOnSurface
        wrapMode: Text.Wrap
        pointSize: Style.fontSizeS
      }
    }
  }
}
