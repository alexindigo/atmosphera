import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Services
import qs.Modules.MainScreen.Backgrounds


/**
 * ScreenCornersBackground - ShapePath component for rendering screen corners
 *
 * Renders concave corners at the screen edges to create a rounded screen effect.
 * Uses the unified shadow system - this ShapePath is a child of the AllBackgrounds Shape container.
 */
ShapePath {
  id: root

  // Required reference to AllBackgrounds shapeContainer
  required property var shapeContainer

  // Required reference to the bar
  required property var bar

  // Corner configuration
  readonly property color cornerColor: Settings.data.general.forceBlackScreenCorners ? Color.black : Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)
  readonly property real cornerRadius: Style.screenRadius
  readonly property real cornerSize: Style.screenRadius

  // Helper properties for margin calculations
  readonly property bool barOnThisMonitor: BarService.isVisible && Settings.data.bar.backgroundOpacity > 0
  readonly property real barMargin: !Settings.data.bar.floating && barOnThisMonitor ? Style.barHeight : 0

  // Determine margins based on bar position
  readonly property real topMargin: Settings.data.bar.position === "top" ? barMargin : 0
  readonly property real bottomMargin: Settings.data.bar.position === "bottom" ? barMargin : 0
  readonly property real leftMargin: Settings.data.bar.position === "left" ? barMargin : 0
  readonly property real rightMargin: Settings.data.bar.position === "right" ? barMargin : 0

  // Screen dimensions
  readonly property real screenWidth: shapeContainer ? shapeContainer.width : 0
  readonly property real screenHeight: shapeContainer ? shapeContainer.height : 0

  // Only show screen corners if enabled and appropriate conditions are met
  readonly property bool shouldShow: Settings.data.general.showScreenCorners && (!Settings.data.ui.panelsAttachedToBar || Settings.data.bar.backgroundOpacity >= 1 || Settings.data.bar.floating)

  // ShapePath configuration
  strokeWidth: -1 // No stroke, fill only
  fillColor: shouldShow ? cornerColor : Color.transparent

  // Smooth color animation
  Behavior on fillColor {
    ColorAnimation {
      duration: Style.animationFast
    }
  }

  // ========== PATH DEFINITION ==========
  // Draws 4 separate corner squares at screen edges
  // Each corner square has a concave arc on the inner diagonal

  // ========== TOP-LEFT CORNER ==========
  // Arc is at the bottom-right of this square (inner diagonal)
  // Start at top-left screen corner
  startX: leftMargin
  startY: topMargin

  // Top edge (moving right)
  PathLine {
    relativeX: cornerSize
    relativeY: 0
  }

  // Right edge (moving down toward arc)
  PathLine {
    relativeX: 0
    relativeY: cornerSize - cornerRadius
  }

  // Concave arc (bottom-right corner of square, curving inward toward screen center)
  PathArc {
    relativeX: -cornerRadius
    relativeY: cornerRadius
    radiusX: cornerRadius
    radiusY: cornerRadius
    direction: PathArc.Counterclockwise
  }

  // Bottom edge (moving left)
  PathLine {
    relativeX: -(cornerSize - cornerRadius)
    relativeY: 0
  }

  // Left edge (moving up) - closes back to start
  PathLine {
    relativeX: 0
    relativeY: -cornerSize
  }

  // ========== TOP-RIGHT CORNER ==========
  // Arc is at the bottom-left of this square (inner diagonal)
  PathMove {
    x: screenWidth - rightMargin - cornerSize
    y: topMargin
  }

  // Top edge (moving right)
  PathLine {
    relativeX: cornerSize
    relativeY: 0
  }

  // Right edge (moving down)
  PathLine {
    relativeX: 0
    relativeY: cornerSize
  }

  // Bottom edge (moving left toward arc)
  PathLine {
    relativeX: -(cornerSize - cornerRadius)
    relativeY: 0
  }

  // Concave arc (bottom-left corner of square, curving inward toward screen center)
  PathArc {
    relativeX: -cornerRadius
    relativeY: -cornerRadius
    radiusX: cornerRadius
    radiusY: cornerRadius
    direction: PathArc.Counterclockwise
  }

  // Left edge (moving up) - closes back to start
  PathLine {
    relativeX: 0
    relativeY: -(cornerSize - cornerRadius)
  }

  // ========== BOTTOM-LEFT CORNER ==========
  // Arc is at the top-right of this square (inner diagonal)
  PathMove {
    x: leftMargin
    y: screenHeight - bottomMargin - cornerSize
  }

  // Top edge (moving right toward arc)
  PathLine {
    relativeX: cornerSize - cornerRadius
    relativeY: 0
  }

  // Concave arc (top-right corner of square, curving inward toward screen center)
  PathArc {
    relativeX: cornerRadius
    relativeY: cornerRadius
    radiusX: cornerRadius
    radiusY: cornerRadius
    direction: PathArc.Counterclockwise
  }

  // Right edge (moving down)
  PathLine {
    relativeX: 0
    relativeY: cornerSize - cornerRadius
  }

  // Bottom edge (moving left)
  PathLine {
    relativeX: -cornerSize
    relativeY: 0
  }

  // Left edge (moving up) - closes back to start
  PathLine {
    relativeX: 0
    relativeY: -cornerSize
  }

  // ========== BOTTOM-RIGHT CORNER ==========
  // Arc is at the top-left of this square (inner diagonal)
  // Start at bottom-right of square (different from other corners!)
  PathMove {
    x: screenWidth - rightMargin
    y: screenHeight - bottomMargin
  }

  // Bottom edge (moving left)
  PathLine {
    relativeX: -cornerSize
    relativeY: 0
  }

  // Left edge (moving up toward arc)
  PathLine {
    relativeX: 0
    relativeY: -(cornerSize - cornerRadius)
  }

  // Concave arc (top-left corner of square, curving inward toward screen center)
  PathArc {
    relativeX: cornerRadius
    relativeY: -cornerRadius
    radiusX: cornerRadius
    radiusY: cornerRadius
    direction: PathArc.Counterclockwise
  }

  // Top edge (moving right)
  PathLine {
    relativeX: cornerSize - cornerRadius
    relativeY: 0
  }

  // Right edge (moving down) - closes back to start
  PathLine {
    relativeX: 0
    relativeY: cornerSize
  }
}
