import QtQuick

// Presentation only: geometry, progress and pulse are owned by the service.
Item {
  id: root
  required property var zone
  required property real progress
  required property bool holding
  required property bool pulse
  required property bool reducedMotion
  required property color accent
  property real depth: 8

  readonly property bool verticalEdge: zone && (zone.edge === "left" || zone.edge === "right")
  readonly property bool reversed: zone && (zone.edge === "right" || zone.edge === "bottom")
  x: !zone ? 0 : zone.edge === "right" ? zone.rect.x + zone.rect.width - depth : zone.rect.x
  y: !zone ? 0 : zone.edge === "bottom" ? zone.rect.y + zone.rect.height - depth : zone.rect.y
  width: !zone ? 0 : verticalEdge ? depth : zone.rect.width
  height: !zone ? 0 : verticalEdge ? zone.rect.height : depth
  opacity: holding ? (pulse ? 1 : progress) : 0

  Behavior on opacity {
    enabled: !root.holding && !root.reducedMotion
    NumberAnimation {
      duration: 75
    }
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: root.verticalEdge ? Gradient.Horizontal : Gradient.Vertical
      GradientStop {
        position: 0
        color: root.reversed ? "transparent" : root.accent
      }
      GradientStop {
        position: 1
        color: root.reversed ? root.accent : "transparent"
      }
    }
  }
}
