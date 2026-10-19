import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

ColumnLayout {
  id: root
  required property var request
  readonly property real choiceRowHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
  function choiceGeometry() {
    var centers = [];
    for (var i = 0; i < choiceRepeater.count; ++i) {
      var delegate = choiceRepeater.itemAt(i);
      if (delegate && delegate.item) centers.push(delegate.item.controlCenter);
    }
    return centers;
  }
  spacing: Style.marginM
  Flow {
    Layout.fillWidth: true
    Layout.preferredHeight: childrenRect.height
    spacing: Style.marginL
    Repeater {
      id: choiceRepeater
      model: root.request.options.choices || []
      Loader {
        id: choice
        required property var modelData
        height: root.choiceRowHeight
        sourceComponent: modelData[2].length ? menuChoice : booleanChoice
        Component {
          id: menuChoice
          RowLayout {
            readonly property real controlCenter: menuControl.mapToItem(root, 0, menuControl.height / 2).y
            spacing: Style.marginM
            NText { text: choice.modelData[1] }
            ChooserComboBox {
              id: menuControl
              accessibleName: choice.modelData[1]
              model: choice.modelData[2].map(pair => ({key: pair[0], name: pair[1]}))
              currentKey: root.request.choiceValues[choice.modelData[0]] || ""
              minimumWidth: 120
              onSelected: key => root.request.setChoice(choice.modelData[0], key)
            }
          }
        }
        Component {
          id: booleanChoice
          FocusScope {
            readonly property real controlCenter: check.mapToItem(root, 0, check.height / 2).y
            implicitWidth: check.implicitWidth
            implicitHeight: check.implicitHeight
            activeFocusOnTab: true
            Accessible.role: Accessible.CheckBox
            Accessible.name: choice.modelData[1]
            Accessible.checked: root.request.choiceValues[choice.modelData[0]] === "true"
            Keys.onSpacePressed: root.request.setChoice(choice.modelData[0], root.request.choiceValues[choice.modelData[0]] === "true" ? "false" : "true")
            NCheckbox {
              id: check
              anchors.fill: parent
              label: choice.modelData[1]
              labelSize: Style.fontSizeM
              checked: root.request.choiceValues[choice.modelData[0]] === "true"
              onToggled: checked => root.request.setChoice(choice.modelData[0], checked ? "true" : "false")
            }
            Rectangle { anchors.fill: parent; color: "transparent"; radius: Style.iRadiusS; border.width: parent.activeFocus ? Style.borderM : 0; border.color: AtmoColor.mPrimary }
          }
        }
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    ChooserComboBox {
      accessibleName: I18n.tr("widgets.file-picker.file-type")
      visible: (root.request.options.filters || []).length > 0
      minimumWidth: 170
      model: (root.request.options.filters || []).map((filter, index) => ({key: String(index), name: filter[0]}))
      currentKey: String((root.request.options.filters || []).findIndex(filter => JSON.stringify(filter) === JSON.stringify(root.request.currentFilter)))
      onSelected: key => root.request.currentFilter = root.request.options.filters[Number(key)]
    }
    Item { Layout.fillWidth: true }
    NText { text: I18n.tr("widgets.file-picker.selection-count", {count: root.request.selection.selectedPaths.length}); pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant }
    ChooserButton { text: I18n.tr("common.cancel"); onClicked: root.request.cancel() }
    ChooserButton { text: root.request.acceptLabel; primary: true; enabled: !root.request.busy; onClicked: root.request.accept() }
  }
}
