import QtQuick
import QtQuick.Shapes
import qs.Commons


/**
 * BarBackground - ShapePath component for rendering the bar background
 *
 * Unified shadow system. This component is a ShapePath that will be
 * a child of the unified AllBackgrounds Shape container.
 *
 * Uses 4-state per-corner system for flexible corner rendering:
 * - State -1: No radius (flat/square corner)
 * - State 0: Normal (inner curve)
 * - State 1: Horizontal inversion (outer curve on X-axis)
 * - State 2: Vertical inversion (outer curve on Y-axis)
 */
ShapePath {
  id: root

  // Required reference to the bar component
  required property var bar

  // Required reference to AllBackgrounds shapeContainer
  required property var shapeContainer

  // Corner radius (from Style)
  readonly property real radius: Style.radiusL

  // Bar position - since bar's parent fills the screen and Shape also fills the screen,
  // we can use bar.x and bar.y directly (they're already in screen coordinates)
  readonly property point barMappedPos: bar ? Qt.point(bar.x, bar.y) : Qt.point(0, 0)

  // Flatten corners if bar is too small (handle null bar)
  readonly property bool shouldFlatten: bar ? (bar.width < radius * 2 || bar.height < radius * 2) : false
  readonly property real effectiveRadius: shouldFlatten ? (bar ? Math.min(bar.width / 2, bar.height / 2) : 0) : radius

  // Helper functions (inlined from ShapeCornerHelper)
  function getMultX(cornerState) {
    return cornerState === 1 ? -1 : 1
  }
  function getMultY(cornerState) {
    return cornerState === 2 ? -1 : 1
  }
  function getArcDirection(multX, multY) {
    return ((multX < 0) !== (multY < 0)) ? PathArc.Counterclockwise : PathArc.Clockwise
  }
  function getCornerRadius(cornerState) {
    // State -1 = no radius (flat corner)
    if (cornerState === -1)
      return 0
    // All other states use effectiveRadius
    return effectiveRadius
  }

  // Per-corner multipliers and radii based on bar's corner states (handle null bar)
  readonly property real tlMultX: bar ? getMultX(bar.topLeftCornerState) : 1
  readonly property real tlMultY: bar ? getMultY(bar.topLeftCornerState) : 1
  readonly property real tlRadius: bar ? getCornerRadius(bar.topLeftCornerState) : 0

  readonly property real trMultX: bar ? getMultX(bar.topRightCornerState) : 1
  readonly property real trMultY: bar ? getMultY(bar.topRightCornerState) : 1
  readonly property real trRadius: bar ? getCornerRadius(bar.topRightCornerState) : 0

  readonly property real brMultX: bar ? getMultX(bar.bottomRightCornerState) : 1
  readonly property real brMultY: bar ? getMultY(bar.bottomRightCornerState) : 1
  readonly property real brRadius: bar ? getCornerRadius(bar.bottomRightCornerState) : 0

  readonly property real blMultX: bar ? getMultX(bar.bottomLeftCornerState) : 1
  readonly property real blMultY: bar ? getMultY(bar.bottomLeftCornerState) : 1
  readonly property real blRadius: bar ? getCornerRadius(bar.bottomLeftCornerState) : 0

  // ShapePath configuration
  strokeWidth: -1 // No stroke, fill only
  fillColor: Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)

  // Starting position (top-left corner, after the arc)
  // Use mapped coordinates relative to the Shape container
  startX: barMappedPos.x + tlRadius * tlMultX
  startY: barMappedPos.y

  // Smooth color animation
  Behavior on fillColor {
    ColorAnimation {
      duration: Style.animationFast
    }
  }

  // ========== PATH DEFINITION ==========
  // Draws a rectangle with potentially inverted corners
  // All coordinates are relative to startX/startY

  // Top edge (moving right)
  PathLine {
    relativeX: (bar ? bar.width : 0) - root.tlRadius * root.tlMultX - root.trRadius * root.trMultX
    relativeY: 0
  }

  // Top-right corner arc
  PathArc {
    relativeX: root.trRadius * root.trMultX
    relativeY: root.trRadius * root.trMultY
    radiusX: root.trRadius
    radiusY: root.trRadius
    direction: root.getArcDirection(root.trMultX, root.trMultY)
  }

  // Right edge (moving down)
  PathLine {
    relativeX: 0
    relativeY: (bar ? bar.height : 0) - root.trRadius * root.trMultY - root.brRadius * root.brMultY
  }

  // Bottom-right corner arc
  PathArc {
    relativeX: -root.brRadius * root.brMultX
    relativeY: root.brRadius * root.brMultY
    radiusX: root.brRadius
    radiusY: root.brRadius
    direction: root.getArcDirection(root.brMultX, root.brMultY)
  }

  // Bottom edge (moving left)
  PathLine {
    relativeX: -((bar ? bar.width : 0) - root.brRadius * root.brMultX - root.blRadius * root.blMultX)
    relativeY: 0
  }

  // Bottom-left corner arc
  PathArc {
    relativeX: -root.blRadius * root.blMultX
    relativeY: -root.blRadius * root.blMultY
    radiusX: root.blRadius
    radiusY: root.blRadius
    direction: root.getArcDirection(root.blMultX, root.blMultY)
  }

  // Left edge (moving up) - closes the path back to start
  PathLine {
    relativeX: 0
    relativeY: -((bar ? bar.height : 0) - root.blRadius * root.blMultY - root.tlRadius * root.tlMultY)
  }

  // Top-left corner arc (back to start)
  PathArc {
    relativeX: root.tlRadius * root.tlMultX
    relativeY: -root.tlRadius * root.tlMultY
    radiusX: root.tlRadius
    radiusY: root.tlRadius
    direction: root.getArcDirection(root.tlMultX, root.tlMultY)
  }
}
