import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root
  required property var request
  readonly property bool selectionCountVisible: selectionCount.visible
  readonly property bool dropdownValuesFit: !filterMenu.visible || !filterMenu.valueElided
  Layout.fillHeight: false
  spacing: Style.marginM

  // Geometry is exposed by the component, without consumers reaching inside.
  function controlGeometry() {
    return [filterMenu, autoExtension, selectionCount, cancelButton, acceptButton].filter(control => control.visible).map(control => {
      // These are direct RowLayout children. Read their properties so a bound
      // geometry projection follows position changes as actions appear/disappear.
      return {name: control.Accessible.name || "selection", x: control.x, y: control.y, width: control.width, height: control.height, center: control.y + control.height / 2};
    });
  }

  ChooserComboBox {
    id: filterMenu
    Layout.fillHeight: true
    Layout.fillWidth: true
    Layout.maximumWidth: implicitWidth
    Layout.minimumWidth: compactWidth
    accessibleName: I18n.tr("widgets.file-picker.file-type")
    visible: (root.request.options.filters || []).length > 0
    minimumWidth: 170
    model: (root.request.options.filters || []).map((filter, index) => ({key: String(index), name: filter[0]}))
    currentKey: String((root.request.options.filters || []).findIndex(filter => JSON.stringify(filter) === JSON.stringify(root.request.currentFilter)))
    onSelected: key => root.request.currentFilter = root.request.options.filters[Number(key)]
  }
  ChooserCheckBox {
    id: autoExtension
    visible: root.request.method === "save" && root.request.preferredSuffix !== ""
    accessibleName: I18n.tr("widgets.file-picker.auto-extension")
    label: accessibleName + " (." + root.request.preferredSuffix + ")"
    checked: root.request.autoExtension
    onToggled: value => root.request.autoExtension = value
  }
  Item { Layout.fillWidth: true }
  NText {
    id: selectionCount
    Layout.fillHeight: true
    verticalAlignment: Text.AlignVCenter
    visible: root.request.method === "open" && root.request.selection.selectedPaths.length > 0
    text: I18n.tr("widgets.file-picker.selection-count", {count: root.request.selection.selectedPaths.length})
    pointSize: Style.fontSizeS
    color: AtmoColor.mOnSurfaceVariant
  }
  ChooserButton {
    id: cancelButton
    Layout.fillHeight: true
    text: I18n.tr("common.cancel")
    onClicked: root.request.cancel()
  }
  ChooserButton {
    id: acceptButton
    Layout.fillHeight: true
    text: root.request.acceptLabel
    primary: true
    visible: !root.request.busy
    onClicked: root.request.accept()
  }
}
