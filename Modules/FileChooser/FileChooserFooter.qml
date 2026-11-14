import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  required property var request
  property bool resizeAvailable: true
  signal resizeRequested(real dx, real dy)
  readonly property bool selectionCountVisible: selectionCount.visible
  readonly property bool dropdownValuesFit: !filterMenu.visible || !filterMenu.valueElided
  Layout.fillHeight: false
  spacing: Style.marginM
  function viewControls() {
    var origin = viewBar.mapToItem(root, 0, 0);
    return viewBar.controls().map(c => Object.assign({}, c, {
                                                       x: c.x + origin.x,
                                                       y: c.y + origin.y
                                                     }));
  }
  function resizeGeometry() {
    var r = viewBar.resizeGeometry(), p = viewBar.mapToItem(root, 0, 0);
    return {
      x: r.x + p.x,
      y: r.y + p.y,
      width: r.width,
      height: r.height
    };
  }

  // Geometry is exposed by the component, without consumers reaching inside.
  function controlGeometry() {
    return [filterMenu, autoExtension, selectionCount, cancelButton, acceptButton].filter(control => control.visible).map(control => {
      // These are direct RowLayout children. Read their properties so a bound
      // geometry projection follows position changes as actions appear/disappear.
      return {
        name: control.Accessible.name || "selection",
        x: control.x + actions.x,
        y: control.y + actions.y,
        width: control.width,
        height: control.height,
        center: control.y + actions.y + control.height / 2
      };
    });
  }

  RowLayout {
    id: actions
    Layout.fillWidth: true
    spacing: Style.marginM
    ChooserComboBox {
      id: filterMenu
      Layout.fillHeight: true
      Layout.fillWidth: true
      Layout.maximumWidth: implicitWidth
      Layout.minimumWidth: compactWidth
      accessibleName: I18n.tr("widgets.file-picker.file-type")
      visible: (root.request.options.filters || []).length > 0
      minimumWidth: 170
      model: (root.request.options.filters || []).map((filter, index) => ({
        key: String(index),
        name: filter[0]
      }))
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
    Item {
      Layout.fillWidth: true
    }
    NText {
      id: selectionCount
      Layout.fillHeight: true
      verticalAlignment: Text.AlignVCenter
      visible: root.request.method === "open" && root.request.selection.selectedPaths.length > 0
      text: I18n.tr("widgets.file-picker.selection-count", {
                      count: root.request.selection.selectedPaths.length
                    })
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
  FileViewControls {
    id: viewBar
    Layout.fillWidth: true
    settings: root.request.viewSettings
    resizeAvailable: root.resizeAvailable
    onResizeRequested: (dx, dy) => root.resizeRequested(dx, dy)
  }
}
