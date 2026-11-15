import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ChooserFocusScope {
  id: root
  required property var operations
  property Item returnFocus: null
  function controlGeometry(target) {
    return [cancelButton, deleteButton].map(item => {
      var rect = item.mapToItem(target, 0, 0, item.width, item.height);
      return {name: item.text, x: rect.x, y: rect.y, width: rect.width, height: rect.height};
    });
  }
  visible: operations.pendingDelete.length > 0
  Accessible.role: Accessible.Dialog
  Accessible.name: I18n.tr("widgets.file-picker.delete-title")
  Accessible.description: operations.pendingDelete.join("\n")
  NInputGuard { target: root; focusTarget: cancelButton; focusOwner: root.returnFocus; focusOnActivation: true }
  Rectangle { anchors.fill: parent; color: Qt.alpha(AtmoColor.mSurface, 0.97); radius: Style.radiusL }
  MouseArea { anchors.fill: parent }
  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.margin2XL, 480 * Style.uiScaleRatio)
    spacing: Style.marginL
    AtmoIcon { Layout.alignment: Qt.AlignHCenter; icon: Icon.trash; pointSize: Style.fontSizeXXXL }
    NText { Layout.fillWidth: true; text: root.Accessible.name; horizontalAlignment: Text.AlignHCenter; pointSize: Style.fontSizeL; elide: Text.ElideRight }
    Rectangle { Layout.fillWidth: true; implicitHeight: Style.borderS; color: AtmoColor.mOutline }
    NText { Layout.fillWidth: true; text: I18n.tr("widgets.file-picker.delete-description", {count: root.operations.pendingDelete.length}); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
    NText { Layout.fillWidth: true; text: root.operations.pendingDelete.map(path => path.slice(path.lastIndexOf("/") + 1)).join(", "); elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter }
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginM
      ChooserButton { id: cancelButton; text: I18n.tr("common.cancel"); primary: true; onClicked: root.operations.declineDelete() }
      ChooserButton { id: deleteButton; text: I18n.tr("widgets.file-picker.delete-permanently"); onClicked: root.operations.confirmDelete() }
    }
  }
}
