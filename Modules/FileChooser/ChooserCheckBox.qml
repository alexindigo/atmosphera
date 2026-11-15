import QtQuick
import qs.Commons
import qs.Widgets

FocusScope {
  id: root
  property string label: ""
  property string accessibleName: label
  property bool checked: false
  readonly property bool valueElided: false
  signal toggled(bool value)
  implicitWidth: check.implicitWidth
  implicitHeight: check.implicitHeight
  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.name: accessibleName
  Accessible.checked: checked
  Accessible.onToggleAction: root.toggled(!root.checked)
  Keys.onSpacePressed: root.toggled(!root.checked)
  NInputGuard {
    target: root
  }
  function controlCenter(relativeTo) {
    return check.mapToItem(relativeTo, 0, check.height / 2).y;
  }
  NCheckbox {
    id: check
    anchors.fill: parent
    label: root.label
    labelSize: Style.fontSizeM
    checked: root.checked
    onToggled: value => root.toggled(value)
  }
  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: Style.iRadiusS
    border.width: root.activeFocus ? Style.borderM : 0
    border.color: AtmoColor.mPrimary
  }
}
