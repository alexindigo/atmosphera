import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets


RowLayout {
  id: root

  // Public properties
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property string suffix: ""
  property string prefix: ""
  property string label: ""
  property string description: ""
  property bool enabled: true
  property bool hovering: false
  property int baseSize: Style.baseWidgetSize

  // Convenience properties for common naming
  property alias minimum: root.from
  property alias maximum: root.to

  signal entered
  signal exited

  Layout.fillWidth: true

  NLabel {
    label: root.label
    description: root.description
  }

  // Main spinbox container
  Rectangle {
    id: spinBoxContainer
    implicitWidth: 120 * scaling
    implicitHeight: (root.baseSize - 4) * scaling
    radius: height * 0.5
    color: Color.mSurfaceVariant
    border.color: (root.hovering || decreaseArea.containsMouse || increaseArea.containsMouse) ? Color.mTertiary : Color.mOutline
    border.width: 1

    Behavior on border.color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    // Mouse area for hover and scroll
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
      onEntered: {
        root.hovering = true
        root.entered()
      }
      onExited: {
        root.hovering = false
        root.exited()
      }
      onWheel: wheel => {
                 if (wheel.angleDelta.y > 0 && root.value < root.to) {
                   let newValue = Math.min(root.to, root.value + root.stepSize)
                   root.value = newValue
                 } else if (wheel.angleDelta.y < 0 && root.value > root.from) {
                   let newValue = Math.max(root.from, root.value - root.stepSize)
                   root.value = newValue
                 }
               }
    }

    // Decrease button (left)
    Item {
      id: decreaseButton
      height:parent.height
      width: height
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      opacity: root.enabled && root.value > root.from ? 1.0 : 0.3


      Item {
        id: leftSemicircle
        width: Math.round(parent.height / 2)
        height: parent.height
        clip: true
        anchors.left: parent.left
        Rectangle {
            width: Math.round(parent.height)
            height: parent.height
            radius: width / 2
            anchors.left: parent.left
            color: decreaseArea.containsMouse ? Color.mTertiary : "transparent"
            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

      Rectangle {
        height: parent.height
        width: parent.width - leftSemicircle.width
        anchors.left: leftSemicircle.right
        gradient: Gradient {
          orientation: Gradient.Horizontal
            GradientStop {
              position: 0.0
              color: decreaseArea.containsMouse ? Color.mTertiary : "transparent"
              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }
            GradientStop {
              position: 1.0
              color: "transparent"
            }
          }
        }

        NIcon {
          anchors.centerIn: parent
          icon: "chevron-left"
          font.pointSize: Style.fontSizeS * scaling
          color: decreaseArea.containsMouse ? Color.mOnPrimary : Color.mPrimary
        }

      MouseArea {
        id: decreaseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled && root.value > root.from
        onClicked: {
          let newValue = Math.max(root.from, root.value - root.stepSize)
          root.value = newValue
        }
      }
    }


    // Increase button (right)
    Item {
      id: increaseButton
      height: parent.height
      width: height
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      opacity: root.enabled && spinBox.value < spinBox.to ? 1.0 : 0.3
      opacity: root.enabled && root.value < root.to ? 1.0 : 0.3


      Item {
        id: rightSemicircle
        width: Math.round(parent.height / 2)
        height: parent.height
        clip: true
        anchors.right: parent.right
        Rectangle {
          width: Math.round(parent.height)
          height: parent.height
          radius: width / 2
          anchors.right: parent.right
          color: increaseArea.containsMouse ? Color.mTertiary : "transparent"
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }
      }

      Rectangle {
        height: parent.height
        width: parent.width - rightSemicircle.width
        anchors.right: rightSemicircle.left
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop {
            position: 1.0
            color: increaseArea.containsMouse ? Color.mTertiary : "transparent"
            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }
          GradientStop {
            position: 0.0
            color: "transparent"
          }
        }
      }

      NIcon {
        anchors.centerIn: parent
        icon: "chevron-right"
        font.pointSize: Style.fontSizeS * scaling
        color: increaseArea.containsMouse ? Color.mOnPrimary : Color.mPrimary
      }

      MouseArea {
        id: increaseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled && root.value < root.to
        onClicked: {
          let newValue = Math.min(root.to, root.value + root.stepSize)
          root.value = newValue
        }
      }
    }

    // Center value display with separate prefix, value, and suffix
    Rectangle {
      id: valueContainer
      anchors.left: decreaseButton.right
      anchors.right: increaseButton.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 4 * scaling
      height: parent.height
      color: "transparent"

      Row {
        anchors.centerIn: parent
        spacing: 0

        // Prefix text (non-editable)
        Text {
          text: root.prefix
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM * scaling
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          visible: root.prefix !== ""
        }

        // Editable number input
        TextInput {
          id: valueInput
          text: root.value.toString()
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM * scaling
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          selectByMouse: true
          enabled: root.enabled

          // Only allow numeric input within range
          validator: IntValidator {
            bottom: root.from
            top: root.to
          }

          Keys.onReturnPressed: {
            applyValue()
            focus = false
          }

          Keys.onEscapePressed: {
            text = root.value.toString()
            focus = false
          }

          onFocusChanged: {
            if (focus) {
              selectAll()
            } else {
              applyValue()
            }
          }

          function applyValue() {
            let newValue = parseInt(text)
            if (!isNaN(newValue)) {
              newValue = Math.max(root.from, Math.min(root.to, newValue))
              root.value = newValue
              text = root.value.toString()
            } else {
              text = root.value.toString()
            }
          }
        }

        // Suffix text (non-editable)
        Text {
          text: root.suffix
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM * scaling
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          visible: root.suffix !== ""
        }
      }
    }
  }
}
