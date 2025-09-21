import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  Layout.fillWidth: true

  property alias text: input.text
  property alias placeholderText: input.placeholderText
  property string label: ""
  property string description: ""
  property alias buttonIcon: button.icon
  property alias buttonTooltip: button.tooltipText
  property alias buttonEnabled: button.enabled
  property real maximumWidth: 0

  signal buttonClicked
  signal inputTextChanged(string text)
  signal inputEditingFinished

  spacing: Style.marginS * scaling

  // Label and description
  NLabel {
    label: root.label
    description: root.description
    visible: root.label !== "" || root.description !== ""
    Layout.fillWidth: true
  }

  // Input field with button
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM * scaling

    // Input field container
    Rectangle {
      id: inputContainer
      Layout.fillWidth: true
      Layout.maximumWidth: root.maximumWidth > 0 ? root.maximumWidth : -1
      implicitHeight: Style.baseWidgetSize * 1.1 * scaling

      radius: Style.radiusM * scaling
      color: Color.mSurface
      border.color: input.activeFocus ? Color.mSecondary : Color.mOutline
      border.width: Math.max(1, Style.borderS * scaling)

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }

      TextField {
        id: input
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.marginM * scaling

        color: Color.mOnSurface
        font.pointSize: Style.fontSizeS * scaling
        font.family: Settings.data.ui.fontDefault
        selectByMouse: true

        background: Item {} // Remove default background since we have our own Rectangle

        onTextChanged: root.inputTextChanged(text)
        onEditingFinished: root.inputEditingFinished()
      }
    }

    // Button
    NIconButton {
      id: button
      baseSize: Style.baseWidgetSize
      onClicked: root.buttonClicked()
    }
  }
}
