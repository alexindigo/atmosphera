import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets


RowLayout {
  id: root

  // Public properties
  property alias value: spinBox.value
  property alias from: spinBox.from
  property alias to: spinBox.to
  property alias stepSize: spinBox.stepSize
  property string suffix: ""
  property string prefix: ""
  property string label: ""
  property string description: ""
  property bool enabled: true
  property bool hovering: false
  property int baseSize: Style.baseWidgetSize

  // Convenience properties for common naming
  property alias minimum: spinBox.from
  property alias maximum: spinBox.to

  signal entered
  signal exited

  Layout.fillWidth: true

  NLabel {
    label: root.label
    description: root.description
  }

  // Value
  Rectangle {
    id: spinBoxContainer
    implicitWidth: 100 * scaling // Wider for better proportions
    implicitHeight: (root.baseSize - 4) * scaling // Slightly shorter than toggle
    radius: height / 2 // Fully rounded like toggle
    color: Color.mSurfaceVariant
    border.color: (root.hovering || decreaseArea.containsMouse || increaseArea.containsMouse) ? Color.mTertiary : Color.mOutline
    border.width: 1

    Behavior on border.color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    // Mouse area for scroll wheel and hover
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
                 if (wheel.angleDelta.y > 0 && spinBox.value < spinBox.to) {
                   spinBox.increase()
                 } else if (wheel.angleDelta.y < 0 && spinBox.value > spinBox.from) {
                   spinBox.decrease()
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
      opacity: root.enabled && spinBox.value > spinBox.from ? 1.0 : 0.3

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
          enabled: root.enabled && spinBox.value > spinBox.from
          onClicked: spinBox.decrease()
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
        enabled: root.enabled && spinBox.value < spinBox.to
        onClicked: spinBox.increase()
      }
    }

    // Center value display
    SpinBox {
      id: spinBox
      anchors.left: decreaseButton.right
      anchors.right: increaseButton.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 4 * scaling
      height: parent.height

      background: Item {}
      up.indicator: Item {}
      down.indicator: Item {}

      font.pointSize: Style.fontSizeM * scaling
      font.family: Settings.data.ui.fontDefault

      from: 0
      to: 100
      stepSize: 1
      editable: false // Only use buttons/scroll
      enabled: root.enabled

      contentItem: Item {
        anchors.fill: parent

        NText {
          anchors.centerIn: parent
          text: root.prefix + spinBox.value + root.suffix
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeM * scaling
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
