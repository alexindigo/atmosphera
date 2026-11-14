import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root
  required property var request
  readonly property bool editingText: pathField.inputItem.activeFocus || filterField.inputItem.activeFocus
  readonly property bool compactPath: crumbs.compact
  readonly property bool editing: pathField.visible
  readonly property var breadcrumbItems: crumbs.items.map(part => ({kind: part.kind, text: part.name, path: part.path}))
  readonly property bool dropdownValuesFit: !sortMenu.valueElided
  readonly property bool transientOpen: pathField.completionOpen || crumbs.menuOpen
  signal listingFocusRequested
  spacing: Style.marginXS

  function controlGeometry() {
    var controls = Array.from(children).filter(item => item.visible).map(item => ({x: item.x, y: item.y, width: item.width, height: item.height, iconOnly: item.iconOnly === true, name: item.Accessible.name || ""}));
    if (!editing) {
      var p = crumbs.mapToItem(root, 0, 0);
      controls = controls.concat(crumbs.controls().map(c => Object.assign({}, c, {x: c.x + p.x, y: c.y + p.y})));
    }
    return controls;
  }
  function pathState() { return {text: pathField.text, suggestions: pathField.suggestions, completionOpen: pathField.completionOpen, menuOpen: crumbs.menuOpen, menuEntries: crumbs.menuEntries, menuGeometry: crumbs.menuGeometry()}; }
  function focusFilter(initial) {
    if (initial !== undefined) request.browser.filterText += initial;
    filterField.inputItem.forceActiveFocus();
  }
  function editPath(initial) {
    pathField.visible = true;
    pathField.text = initial === undefined ? request.browser.currentPath : initial;
    pathField.inputItem.forceActiveFocus();
    if (initial === undefined) pathField.inputItem.selectAll();
  }
  function dismissTransient() { pathField.dismissCompletion(); crumbs.dismissMenu(); }
  function leavePathEditing() { dismissTransient(); pathField.visible = false; listingFocusRequested(); }
  function breadcrumbGeometry() { return crumbs.geometry(); }

  ChooserButton { icon: Icon.chevronLeft; tooltipText: I18n.tr("widgets.file-picker.back"); visible: root.request.browser.canBack; onClicked: root.request.browser.back() }
  ChooserButton { icon: Icon.chevronRight; tooltipText: I18n.tr("widgets.file-picker.forward"); visible: root.request.browser.canForward; onClicked: root.request.browser.forward() }
  ChooserButton { icon: Icon.filepickerArrowUp; tooltipText: I18n.tr("widgets.file-picker.parent-folder"); visible: root.request.browser.currentPath !== "" && root.request.browser.currentPath !== "/"; onClicked: root.request.browser.up() }
  Item {
    Layout.fillWidth: true
    Layout.minimumWidth: crumbs.minimumWidth
    implicitHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
    FileBreadcrumbs { id: crumbs; anchors.fill: parent; visible: !root.editing; browser: root.request.browser; focusOwner: pathField.inputItem; onEditRequested: root.editPath() }
    ChooserPathField {
      id: pathField
      anchors.fill: parent
      visible: false
      accessibleName: I18n.tr("widgets.file-picker.location")
      basePath: root.request.browser.currentPath
      showHidden: root.request.browser.showHidden
      directoriesOnly: true
      onAccepted: { dismissCompletion(); root.request.submitPath(text, "location"); }
    }
  }
  ChooserTextField {
    id: filterField
    Layout.fillWidth: true
    Layout.minimumWidth: 110 * Style.uiScaleRatio
    Layout.preferredWidth: 180 * Style.uiScaleRatio
    Layout.maximumWidth: 220 * Style.uiScaleRatio
    icon: Icon.search
    accessibleName: I18n.tr("widgets.file-picker.filter-names")
    placeholderText: accessibleName
    text: root.request.browser.filterText
    onTextEdited: root.request.browser.filterText = text
    onAccepted: root.listingFocusRequested()
  }
  ChooserButton { icon: ({type: "svg", source: Qt.resolvedUrl("folder-plus.svg")}); tooltipText: I18n.tr("widgets.file-picker.new-folder"); onClicked: root.request.beginCreateFolder() }
  ChooserButton { icon: Icon.filepickerRefresh; tooltipText: I18n.tr("widgets.file-picker.refresh"); onClicked: root.request.browser.refresh() }
  ChooserComboBox {
    id: sortMenu
    Layout.fillWidth: true
    Layout.minimumWidth: compactWidth
    Layout.maximumWidth: implicitWidth
    minimumWidth: 150
    accessibleName: I18n.tr("widgets.file-picker.sort-by")
    model: [
      {key: "name", name: I18n.tr("widgets.file-picker.name")},
      {key: "size", name: I18n.tr("widgets.file-picker.size")},
      {key: "type", name: I18n.tr("widgets.file-picker.type")},
      {key: "modified", name: I18n.tr("widgets.file-picker.modified")}
    ]
    currentKey: root.request.browser.sortKey
    onSelected: key => root.request.browser.sortKey = key
  }
  ChooserButton { icon: root.request.browser.sortDescending ? "sort-descending" : "sort-ascending"; tooltipText: I18n.tr("widgets.file-picker.reverse-sort"); onClicked: root.request.browser.sortDescending = !root.request.browser.sortDescending }
  ChooserButton { icon: Icon.filepickerEye; tooltipText: I18n.tr("widgets.file-picker.show-hidden"); textColor: root.request.browser.showHidden ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant; onClicked: root.request.browser.showHidden = !root.request.browser.showHidden }
  ChooserButton { icon: Icon.filepickerLayoutGrid; tooltipText: I18n.tr("widgets.file-picker.grid-view"); textColor: root.request.viewMode === "grid" ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant; onClicked: root.request.viewMode = "grid" }
  ChooserButton { icon: Icon.filepickerList; tooltipText: I18n.tr("widgets.file-picker.list-view"); textColor: root.request.viewMode === "list" ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant; onClicked: root.request.viewMode = "list" }
}
