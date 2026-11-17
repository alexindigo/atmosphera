import QtQuick

// Presentation only: geometry, progress and pulse are owned by the service.
Item {
  id: root
  required property var zone
  required property real progress
  required property bool holding
  required property bool pulse
  required property bool wall
  required property bool reducedMotion
  required property color accent
  property real depth: 8
  property real wallPhase: 0
  readonly property real recoil: wall && !reducedMotion ? Math.sin(wallPhase * Math.PI) * Math.min(2, depth) : 0
  onWallChanged: {
    if (wall) {
      wallPhase = 0;
      wallAnimation.restart();
    } else {
      wallAnimation.stop();
    }
  }
  NumberAnimation on wallPhase {
    id: wallAnimation
    running: false
    from: 0
    to: 1
    duration: 160
  }

  readonly property bool verticalEdge: zone && (zone.edge === "left" || zone.edge === "right")
  readonly property bool reversed: zone && (zone.edge === "right" || zone.edge === "bottom")
  x: !zone ? 0 : zone.edge === "right" ? zone.rect.x + zone.rect.width - depth : zone.rect.x
  y: !zone ? 0 : zone.edge === "bottom" ? zone.rect.y + zone.rect.height - depth : zone.rect.y
  width: !zone ? 0 : verticalEdge ? depth : zone.rect.width
  height: !zone ? 0 : verticalEdge ? zone.rect.height : depth
  // Reduced motion keeps a short steady cap, then fades without displacement.
  opacity: holding ? (wall ? (reducedMotion ? (wallPhase < 0.5 ? 0.75 : (1 - wallPhase) * 1.5) : 0.75 * (1 - wallPhase)) : pulse ? 1 : progress) : 0

  Behavior on opacity {
    enabled: !root.holding && !root.reducedMotion
    NumberAnimation {
      duration: 75
    }
  }

  Rectangle {
    x: root.verticalEdge && root.reversed ? root.recoil : 0
    y: !root.verticalEdge && root.reversed ? root.recoil : 0
    width: parent.width - (root.verticalEdge ? root.recoil : 0)
    height: parent.height - (root.verticalEdge ? 0 : root.recoil)
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
