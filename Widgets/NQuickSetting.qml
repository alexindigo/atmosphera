import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.Commons
import qs.Services

Rectangle {
  id: root

  // Public properties
  property string text: ""
  property string icon: ""
  property string tooltipText: ""
  property bool enabled: true
  property bool active: false
  property bool compact: false
  property string style: "modern" // "modern" or "classic"

  // Styling properties
  property real fontSize: Style.fontSizeS * scaling
  property int fontWeight: Style.fontWeightMedium
  property real iconSize: Style.fontSizeL * scaling
  property real cornerRadius: Style.radiusM * scaling

  // Colors - Style-dependent colors
  property color backgroundColor: style === "classic" ? Color.mSurfaceVariant : Color.mSurface
  property color textColor: Color.mOnSurface
  property color iconColor: style === "classic" ? Color.mPrimary : (active ? Color.mPrimary : Color.mOnSurface)
  property color borderColor: Color.mOutline
  property color hoverColor: style === "classic" ? Color.mTertiary : Color.mPrimary
  property color pressedColor: style === "classic" ? Color.mTertiary : Qt.darker(Color.mPrimary, 1.1)
  property color hoverTextColor: Color.mOnPrimary
  property color hoverIconColor: style === "classic" ? Color.mOnTertiary : Color.mOnPrimary

  // Signals
  signal clicked
  signal rightClicked
  signal middleClicked

  // Internal properties
  property bool hovered: false
  property bool pressed: false
  property real scaling: 1.0

  // Dimensions - Style-dependent sizing
  implicitWidth: {
    if (style === "classic") {
      return Style.baseWidgetSize * scaling
    }
    return compact ? Math.max(100 * scaling, contentRow.implicitWidth + (Style.marginL * scaling)) : Math.max(120 * scaling, contentRow.implicitWidth + (Style.marginL * scaling))
  }
  implicitHeight: {
    if (style === "classic") {
      return Style.baseWidgetSize * scaling
    }
    return compact ? Math.max(48 * scaling, contentRow.implicitHeight + (Style.marginM * scaling)) : Math.max(56 * scaling, contentRow.implicitHeight + (Style.marginL * scaling))
  }

  // Appearance - Style-dependent styling
  radius: style === "classic" ? width * 0.5 : cornerRadius
  color: {
    if (!enabled)
      return Qt.lighter(Color.mSurface, 1.1)
    if (pressed)
      return pressedColor
    if (hovered)
      return hoverColor
    return backgroundColor
  }

  border.width: style === "classic" ? Math.max(1, Style.borderS * scaling) : 0
  border.color: style === "classic" ? borderColor : "transparent"

  opacity: enabled ? (style === "classic" ? Style.opacityFull : 1.0) : (style === "classic" ? Style.opacityMedium : 0.6)

  // Smooth animations
  Behavior on color {
    ColorAnimation {
      duration: style === "classic" ? Style.animationNormal : Style.animationFast
      easing.type: style === "classic" ? Easing.InOutQuad : Easing.OutCubic
    }
  }

  Behavior on border.color {
    ColorAnimation {
      duration: style === "classic" ? Style.animationNormal : Style.animationFast
      easing.type: style === "classic" ? Easing.InOutQuad : Easing.OutCubic
    }
  }

  Behavior on scale {
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  // Hover scale effect
  scale: hovered ? 1.02 : 1.0

  // Subtle shadow/elevation effect
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Qt.rgba(0, 0, 0, 0.1)
    visible: active
    z: -1

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  // Modern style - icon above text
  ColumnLayout {
    id: contentRow
    anchors.centerIn: parent
    spacing: Style.marginXXS * scaling
    visible: root.style !== "classic"

    // Icon
    NIcon {
      Layout.alignment: Qt.AlignHCenter
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

    // Text content
    NText {
      Layout.alignment: Qt.AlignHCenter
      visible: root.text !== "" && !compact
      text: root.text
      pointSize: root.fontSize
      font.weight: root.fontWeight
      color: {
        if (!root.enabled)
          return Color.mOnSurfaceVariant
        if (root.hovered)
          return root.hoverTextColor
        return root.textColor
      }
      elide: Text.ElideRight

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  // Classic style - EXACTLY like NIconButton (icon + text)
  RowLayout {
    anchors.centerIn: parent
    visible: root.style === "classic"
    spacing: Style.marginXS * scaling

    NIcon {
      visible: root.icon !== ""
      icon: root.icon
      pointSize: Style.fontSizeM * scaling
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

    NText {
      visible: root.text !== ""
      text: root.text
      pointSize: root.fontSize
      font.weight: root.fontWeight
      color: {
        if (!root.enabled)
          return Color.mOnSurfaceVariant
        if (root.hovered)
          return root.hoverTextColor
        return root.textColor
      }

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  // Mouse interaction with enhanced feedback
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
                 root.scale = 0.95
                 if (tooltipText) {
                   TooltipService.hide()
                 }
               }

    onReleased: mouse => {
                  root.pressed = false
                  root.scale = 1.0

                  if (mouse.button === Qt.LeftButton) {
                    root.clicked()
                  } else if (mouse.button === Qt.RightButton) {
                    root.rightClicked()
                  } else if (mouse.button === Qt.MiddleButton) {
                    root.middleClicked()
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

  // Ripple effect for M3-style interaction feedback
  Rectangle {
    id: ripple
    anchors.fill: parent
    radius: parent.radius
    color: Qt.rgba(1, 1, 1, 0.2)
    scale: 0
    opacity: 0
    visible: false

    SequentialAnimation {
      id: rippleAnimation
      running: false

      ParallelAnimation {
        NumberAnimation {
          target: ripple
          property: "scale"
          from: 0
          to: 1.2
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
        NumberAnimation {
          target: ripple
          property: "opacity"
          from: 0.6
          to: 0
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  // Trigger ripple effect on click
  Connections {
    target: root
    function onClicked() {
      ripple.visible = true
      rippleAnimation.start()
    }
  }

  // Clean up ripple after animation
  Connections {
    target: rippleAnimation
    function onFinished() {
      ripple.visible = false
      ripple.scale = 0
      ripple.opacity = 0
    }
  }
}
