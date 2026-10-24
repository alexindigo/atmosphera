import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

// Request-owned additions, visually distinct from the picker's permanent row.
Rectangle {
  id: root
  required property var request
  readonly property real rowHeight: Style.baseWidgetSize * 1.1 * Style.uiScaleRatio
  Layout.minimumWidth: Math.max(0, ...Array.from(flow.children).map(item => item.width)) + Style.margin2L
  Layout.minimumHeight: implicitHeight
  Layout.fillHeight: false
  implicitHeight: flow.height + Style.margin2L + Style.borderS
  color: AtmoColor.mSurfaceVariant

  function controlGeometry() {
    return Array.from(flow.children).filter(item => item.visible && item.width > 0 && item.height > 0).map(item => {
      var rect = item.mapToItem(root, 0, 0, item.width, item.height);
      return {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height
      };
    });
  }

  function choiceGeometry() {
    var centers = [];
    for (var i = 0; i < choices.count; ++i) {
      var delegate = choices.itemAt(i);
      if (delegate && delegate.item)
        centers.push(delegate.item.controlCenter());
    }
    return centers;
  }

  function choiceValuesFit() {
    for (var i = 0; i < choices.count; ++i) {
      var delegate = choices.itemAt(i);
      if (!delegate || !delegate.item || delegate.item.valueElided)
        return false;
    }
    return true;
  }

  Flow {
    id: flow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.marginL
    height: childrenRect.height
    spacing: Style.marginL
    RowLayout {
      height: root.rowHeight
      spacing: Style.marginM
      IconImage {
        visible: root.request.appIcon !== ""
        implicitWidth: Style.fontSizeL * Style.uiScaleRatio
        implicitHeight: implicitWidth
        source: root.request.appIcon ? Quickshell.iconPath(root.request.appIcon) : ""
      }
      NText {
        text: root.request.appOptionsLabel
        pointSize: Style.fontSizeM
        color: AtmoColor.mOnSurfaceVariant
      }
    }
    Repeater {
      id: choices
      model: root.request.choices
      Loader {
        id: choice
        required property var modelData
        height: root.rowHeight
        sourceComponent: modelData[2].length ? menuChoice : booleanChoice
        Component {
          id: menuChoice
          RowLayout {
            readonly property bool valueElided: menuControl.valueElided
            function controlCenter() {
              return menuControl.mapToItem(root, 0, menuControl.height / 2).y;
            }
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
            id: booleanControl
            NInputGuard {
              target: booleanControl
            }
            readonly property bool valueElided: false
            function controlCenter() {
              return check.mapToItem(root, 0, check.height / 2).y;
            }
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
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.borderS
    color: AtmoColor.mOutline
  }
}
