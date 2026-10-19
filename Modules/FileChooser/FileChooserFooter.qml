import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Files
import qs.Widgets

ColumnLayout {
  id: root
  required property var request
  readonly property real choiceRowHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
  readonly property bool selectionCountVisible: selectionCount.visible
  function controlGeometry() {
    return Array.from(choiceFlow.children).concat(Array.from(actions.children)).filter(item => item.visible && item.width > 0 && item.height > 0).map(item => {
      var rect = item.mapToItem(root, 0, 0, item.width, item.height);
      return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
    });
  }
  function choiceGeometry() {
    var centers = [];
    for (var i = 0; i < choiceRepeater.count; ++i) {
      var delegate = choiceRepeater.itemAt(i);
      if (delegate && delegate.item)
        centers.push(delegate.item.controlCenter);
    }
    return centers;
  }
  spacing: Style.marginM
  Flow {
    id: choiceFlow
    Layout.fillWidth: true
    Layout.minimumWidth: Math.max(0, ...Array.from(children).map(item => item.width))
    Layout.minimumHeight: childrenRect.height
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
            NText {
              text: choice.modelData[1]
            }
            ChooserComboBox {
              id: menuControl
              accessibleName: choice.modelData[1]
              model: choice.modelData[2].map(pair => ({
                key: pair[0],
                name: pair[1]
              }))
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
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              radius: Style.iRadiusS
              border.width: parent.activeFocus ? Style.borderM : 0
              border.color: AtmoColor.mPrimary
            }
          }
        }
      }
    }
  }
  RowLayout {
    id: actions
    Layout.fillWidth: true
    spacing: Style.marginM
    ChooserComboBox {
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
    Item {
      Layout.fillWidth: true
    }
    NText {
      id: selectionCount
      visible: root.request.method === "open" && root.request.selection.selectedPaths.length > 0
      text: I18n.tr("widgets.file-picker.selection-count", {
                      count: root.request.selection.selectedPaths.length
                    })
      pointSize: Style.fontSizeS
      color: AtmoColor.mOnSurfaceVariant
    }
    ChooserButton {
      text: I18n.tr("common.cancel")
      onClicked: root.request.cancel()
    }
    ChooserButton {
      text: root.request.acceptLabel
      primary: true
      enabled: !root.request.busy
      onClicked: root.request.accept()
    }
  }
}
