import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  // Public properties
  property string label: ""
  property string description: ""
  property string placeholderText: ""
  property string text: ""
  property string actionButtonText: "Test"
  property string actionButtonIcon: "play_arrow"
  property bool actionButtonEnabled: text !== ""

  // Signals
  signal editingFinished
  signal actionClicked

  // Internal properties
  property real scaling: 1.0

  // Label
  NText {
    text: root.label
    font.pointSize: Style.fontSizeL * scaling
    font.weight: Style.fontWeightBold
    color: Color.mOnSurface
    Layout.fillWidth: true
  }

  // Description
  NText {
    text: root.description
    font.pointSize: Style.fontSizeS * scaling
    color: Color.mOnSurfaceVariant
    wrapMode: Text.Wrap
    Layout.fillWidth: true
  }

  // Input and button row
  RowLayout {
    spacing: Style.marginM * scaling
    Layout.fillWidth: true

    NTextInput {
      id: textInput
      placeholderText: root.placeholderText
      text: root.text
      onEditingFinished: {
        root.text = text
        root.editingFinished()
      }
      Layout.fillWidth: true
    }

    Item {
      Layout.fillWidth: true
    }

    NButton {
      text: root.actionButtonText
      icon: root.actionButtonIcon
      backgroundColor: Color.mSecondary
      textColor: Color.mOnSecondary
      hoverColor: Color.mTertiary
      pressColor: Color.mPrimary
      enabled: root.actionButtonEnabled
      Layout.fillWidth: false
      onClicked: {
        root.actionClicked()
      }
    }
  }
}
