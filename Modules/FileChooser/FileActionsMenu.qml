import QtQuick
import qs.Commons

ChooserMenu {
  id: root
  required property var request
  property bool backgroundMenu: false
  property point anchorPosition: Qt.point(0, 0)
  x: Math.max(0, Math.min((parent ? parent.width : width) - width, anchorPosition.x))
  y: Math.max(0, Math.min((parent ? parent.height : height) - height, anchorPosition.y))
  maximumHeight: Math.min(440 * Style.uiScaleRatio, parent ? parent.height : 440 * Style.uiScaleRatio)
  readonly property var operations: request.browser.operations
  title: I18n.tr(backgroundMenu ? "widgets.file-picker.folder-actions" : "widgets.file-picker.file-actions")
  function action(key, label) { return {key: key, name: I18n.tr("widgets.file-picker." + label)}; }
  entries: {
    var rows = [];
    if (!backgroundMenu && operations.targets().length && operations.available) {
      if (operations.targets().length === 1) rows.push(action("rename", "rename"));
      rows.push(action("trash", "move-to-trash"), action("delete", "delete-permanently"));
    }
    if (operations.available) rows.push(action("new", "new-folder"));
    if (backgroundMenu || operations.targets().length) rows.push(action("copy", "copy-path"));
    rows.push({key: "hidden", name: I18n.tr("widgets.file-picker.show-hidden"), checked: request.browser.showHidden});
    rows.push({key: "sort", name: I18n.tr("widgets.file-picker.sort-by"), children: ["name", "size", "type", "modified"].map(key => ({key: "sort-" + key, name: I18n.tr("widgets.file-picker." + key), checked: request.browser.sortKey === key})).concat([{key: "reverse", name: I18n.tr("widgets.file-picker.reverse-sort"), checked: request.browser.sortDescending}])});
    rows.push({key: "view", name: I18n.tr("widgets.file-picker.view"), children: ["grid", "list"].map(key => ({key: "view-" + key, name: I18n.tr("widgets.file-picker." + key + "-view"), checked: request.viewMode === key}))});
    rows.push(action("refresh", "refresh"));
    return rows;
  }
  onTriggered: entry => {
    if (entry.key === "rename") operations.beginRename();
    else if (entry.key === "trash") operations.trash();
    else if (entry.key === "delete") operations.requestDelete();
    else if (entry.key === "new") request.beginCreateFolder();
    else if (entry.key === "copy") operations.copyPath(backgroundMenu);
    else if (entry.key === "hidden") request.browser.showHidden = !request.browser.showHidden;
    else if (entry.key === "reverse") request.browser.sortDescending = !request.browser.sortDescending;
    else if (entry.key.startsWith("sort-")) request.browser.sortKey = entry.key.slice(5);
    else if (entry.key.startsWith("view-")) request.viewMode = entry.key.slice(5);
    else if (entry.key === "refresh") request.browser.refresh();
  }
}
