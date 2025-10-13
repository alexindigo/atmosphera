import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.Commons
import qs.Services

Rectangle {
  id: root

  // Public properties
  property string icon: ""
  property string tooltipText: ""
  property bool enabled: true
  property bool hot: false

  // Styling properties
  property real iconSize: Style.fontSizeM
  property real cornerRadius: Style.radiusS

  // Internal properties
  property bool hovered: false
  property bool pressed: false

  // Colors
  property color backgroundColor: {
    if (pressed) {
      return Color.mTertiary
    }
    if (hot) {
      return Color.mPrimary
    }
    return Color.mSurface
  }
  property color iconColor: {
    if (pressed) {
      return Color.mOnTertiary
    }
    if (hot) {
      return Color.mOnPrimary
    }
    return Color.mOnSurface
  }
  property color hoverColor: Color.mTertiary
  property color hoverIconColor: Color.mOnTertiary

  // Signals
  signal clicked
  signal rightClicked
  signal middleClicked

  // Dimensions
  implicitWidth: Style.baseWidgetSize * 0.8
  implicitHeight: Style.baseWidgetSize * 0.8

  // Appearance
  radius: cornerRadius
  color: {
    if (!enabled)
      return Qt.lighter(Color.mSurface, 1.1)
    if (hovered)
      return hoverColor
    return backgroundColor
  }

  border.width: 0
  opacity: enabled ? 1.0 : 0.6

  Behavior on color {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  Behavior on scale {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  // Icon
  NIcon {
    anchors.centerIn: parent
    visible: root.icon !== ""
    icon: root.icon
    pointSize: root.iconSize
    color: {
      if (!root.enabled)
        return Color.mOnSurfaceVariant
      if (root.hovered)
        return root.hoverIconColor
      return root.iconColor
    }

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    onEntered: {
      root.hovered = true
      if (tooltipText) {
        TooltipService.show(Screen, root, root.tooltipText)
      }
    }

    onExited: {
      root.hovered = false
      if (tooltipText) {
        TooltipService.hide()
      }
    }

    onPressed: mouse => {
                 root.pressed = true
                 root.scale = 0.92
                 if (tooltipText) {
                   TooltipService.hide()
                 }
               }

    onReleased: mouse => {
                  root.scale = 1.0
                  root.pressed = false

                  // Only trigger actions if released while hovering
                  if (root.hovered) {
                    if (mouse.button === Qt.LeftButton) {
                      root.clicked()
                    } else if (mouse.button === Qt.RightButton) {
                      root.rightClicked()
                    } else if (mouse.button === Qt.MiddleButton) {
                      root.middleClicked()
                    }
                  }
                }

    onCanceled: {
      root.hovered = false
      root.pressed = false
      root.scale = 1.0
      if (tooltipText) {
        TooltipService.hide()
      }
    }
  }
}
