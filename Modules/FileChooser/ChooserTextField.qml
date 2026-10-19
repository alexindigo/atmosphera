import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// NTextInput fixes its focused border to mSecondary. This local presentation
// uses the same shell typography/spacing with the chooser's single accent.
ColumnLayout {
  id: root
  property string label: ""
  property string accessibleName: label
  property real fontSize: Style.fontSizeM
  property alias text: field.text
  property alias inputItem: field
  signal accepted
  signal textEdited
  spacing: Style.marginS
  NText { visible: root.label !== ""; text: root.label; pointSize: Style.fontSizeS; color: AtmoColor.mOnSurfaceVariant }
  NText { id: typography; visible: false; pointSize: root.fontSize }
  TextField {
    id: field
    Layout.fillWidth: true
    implicitHeight: Style.baseWidgetSize * 1.25 * Style.uiScaleRatio
    color: AtmoColor.mOnSurface
    font: typography.font
    leftPadding: Style.marginL
    rightPadding: Style.marginL
    selectByMouse: true
    Accessible.name: root.accessibleName
    onAccepted: root.accepted()
    onTextEdited: root.textEdited()
    background: Rectangle {
      color: AtmoColor.mSurface
      radius: Style.iRadiusS
      border.width: field.activeFocus ? Style.borderM : Style.borderS
      border.color: field.activeFocus ? AtmoColor.mPrimary : AtmoColor.mOutline
    }
  }
}
