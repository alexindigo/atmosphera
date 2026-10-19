import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

RowLayout {
  id: root
  required property var request
  readonly property bool editing: pathField.visible
  readonly property var pathParts: request.browser.currentPath === "/" ? ["/"] : request.browser.currentPath.split("/").filter(part => part !== "")
  signal listingFocusRequested
  spacing: Style.marginXS

  function editPath(initial) {
    pathField.visible = true;
    pathField.text = initial === undefined ? request.browser.currentPath : initial;
    pathField.inputItem.forceActiveFocus();
    if (initial === undefined)
      pathField.inputItem.selectAll();
  }
  function leavePathEditing() {
    pathField.visible = false;
    listingFocusRequested();
  }

  ChooserButton {
    icon: Icon.chevronLeft
    tooltipText: I18n.tr("widgets.file-picker.back")
    enabled: root.request.browser.canBack
    onClicked: root.request.browser.back()
  }
  ChooserButton {
    icon: Icon.chevronRight
    tooltipText: I18n.tr("widgets.file-picker.forward")
    enabled: root.request.browser.canForward
    onClicked: root.request.browser.forward()
  }
  ChooserButton {
    icon: Icon.filepickerArrowUp
    tooltipText: I18n.tr("widgets.file-picker.parent-folder")
    onClicked: root.request.browser.up()
  }
  Item {
    Layout.fillWidth: true
    Layout.minimumWidth: 100 * Style.uiScaleRatio
    implicitHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      radius: Style.iRadiusS
      border.color: AtmoColor.mPrimary
      border.width: pathButton.activeFocus ? Style.borderM : 0
    }
    Item {
      id: pathButton
      anchors.fill: parent
      visible: !root.editing
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: root.request.browser.currentPath
      Keys.onReturnPressed: root.editPath()
      Keys.onSpacePressed: root.editPath()
      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.marginXS
        spacing: Style.marginXS
        NText { visible: root.pathParts.length > 3; text: "…"; color: AtmoColor.mOnSurfaceVariant }
        Repeater {
          model: root.pathParts.slice(-3)
          RowLayout {
            required property string modelData
            required property int index
            Layout.fillWidth: true
            spacing: Style.marginXS
            AtmoIcon { visible: index > 0 || root.pathParts.length > 3; icon: Icon.chevronRight; color: AtmoColor.mOnSurfaceVariant; pointSize: Style.fontSizeS }
            NText { Layout.fillWidth: true; text: modelData; elide: Text.ElideMiddle; pointSize: Style.fontSizeM; color: AtmoColor.mOnSurface }
          }
        }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: root.editPath() }
    }
    ChooserTextField {
      id: pathField
      anchors.fill: parent
      visible: false
      fontSize: Style.fontSizeM
      accessibleName: I18n.tr("widgets.file-picker.location")
      onAccepted: {
        root.request.browser.navigate(text);
        root.leavePathEditing();
      }
    }
  }
  ChooserButton {
    icon: Icon.filepickerRefresh
    tooltipText: I18n.tr("widgets.file-picker.refresh")
    onClicked: root.request.browser.refresh()
  }
  ChooserComboBox {
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
  ChooserButton {
    text: root.request.browser.sortDescending ? "↓" : "↑"
    tooltipText: I18n.tr("widgets.file-picker.reverse-sort")
    onClicked: root.request.browser.sortDescending = !root.request.browser.sortDescending
  }
  ChooserButton {
    icon: Icon.filepickerEye
    tooltipText: I18n.tr("widgets.file-picker.show-hidden")
    textColor: root.request.browser.showHidden ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
    onClicked: root.request.browser.showHidden = !root.request.browser.showHidden
  }
  ChooserButton {
    icon: Icon.filepickerLayoutGrid
    tooltipText: I18n.tr("widgets.file-picker.grid-view")
    textColor: root.request.viewMode === "grid" ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
    onClicked: root.request.viewMode = "grid"
  }
  ChooserButton {
    icon: Icon.filepickerList
    tooltipText: I18n.tr("widgets.file-picker.list-view")
    textColor: root.request.viewMode === "list" ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
    onClicked: root.request.viewMode = "list"
  }
}
