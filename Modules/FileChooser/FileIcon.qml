import QtQuick
import QtQuick.Shapes
import qs.Services.Files
import "FileIconPaths.js" as Paths

Item {
  id: root
  required property var descriptor
  property bool compact: false
  readonly property var paints: FileTypes.iconColors(descriptor)
  readonly property bool folder: descriptor.type === "folder"
  readonly property var mark: Paths.glyph(descriptor.type, descriptor.folder, compact)
  implicitWidth: compact ? 20 : 96
  implicitHeight: implicitWidth
  opacity: descriptor.hidden ? .5 : 1
  // Opacity belongs to the finished illustration, never its overlapping paints.
  layer.enabled: true

  // Native optical canvases keep the list a drawing, not a miniature grid icon.
  Item {
    width: root.compact ? 20 : 64
    height: width
    anchors.centerIn: parent
    scale: Math.min(root.width / width, root.height / height)
    Shape {
      anchors.fill: parent
      ShapePath {
        strokeColor: root.folder ? root.paints.ink : "transparent"
        strokeWidth: root.compact ? .65 : .75
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: root.folder ? root.paints.haze : "transparent"
        PathSvg { path: root.folder ? (root.compact ? "M2 8V4.8Q2 3 3.8 3H7.5L10 5.5H16.5Q18.5 5.5 18.5 7.5V15H2Z" : "M7 25V13Q7 7 13 7H27L34 14H52Q59 14 59 21V49H7Z") : "" }
      }
      ShapePath {
        strokeColor: root.paints.ink
        strokeWidth: root.compact ? .8 : .95
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: root.paints.face
        fillGradient: root.compact ? null : paint
        PathSvg {
          path: root.folder ? (root.compact ? "M1 8.5Q1 7 2.8 7H17.5Q19 7 18.8 8.8L18.1 15.8Q18 17.5 16.2 17.5H2.8Q1 17.5 1 15.8Z" : "M2 28Q2 21 9 21H56Q63 21 62 28L59.2 53Q58.5 59 52.5 59H9Q2 59 2 52Z") : (root.compact ? "M4 1.3H11.8L18 7V16.7Q18 18.7 16 18.7H4Q2 18.7 2 16.7V3.3Q2 1.3 4 1.3Z" : "M13 3H40Q42 3 44 5L56 17Q58 19 58 22V55Q58 61 52 61H13Q7 61 7 55V9Q7 3 13 3Z")
        }
      }
      ShapePath {
        strokeColor: root.compact ? "transparent" : root.paints.ink
        strokeWidth: 1.3
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: "transparent"
        PathSvg { path: root.compact ? "" : root.folder ? "M62 28L59.2 53Q58.5 59 52.5 59H10" : "M58 23V55Q58 61 52 61H15" }
      }
      ShapePath {
        strokeColor: root.folder ? "transparent" : root.paints.ink
        strokeWidth: root.compact ? .55 : .75
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: root.paints.haze
        PathSvg { path: root.folder ? "" : root.compact ? "M11.8 1.7L17.6 7H13Q11.8 7 11.8 5.8Z" : "M41 4.1L57 19H46Q41 19 41 14Z" }
      }
      ShapePath {
        strokeColor: root.paints.highlight
        strokeWidth: 1.25
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: "transparent"
        PathSvg { path: root.compact ? "" : root.folder ? "M5 40V29Q5 24 10 24H44" : "M10 25V10Q10 6 14 6H36" }
      }
    }
    // A single lowered impression behind the raised, lighter folder mark.
    Shape {
      anchors.fill: parent
      visible: root.folder && !root.compact
      transform: Translate { y: .8 }
      ShapePath {
        strokeColor: root.paints.embossShadow
        strokeWidth: 2.6
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: "transparent"
        PathSvg { path: root.mark.line }
      }
    }
    Shape {
      anchors.fill: parent
      ShapePath {
        strokeColor: root.paints[root.mark.paint]
        strokeWidth: root.mark.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        fillColor: "transparent"
        PathSvg { path: root.mark.line }
      }
    }
    Shape {
      anchors.fill: parent
      transform: Rotation {
        origin.x: root.mark.centerX
        origin.y: root.mark.centerY
        angle: root.mark.rotation
      }
      ShapePath {
        strokeColor: "transparent"
        fillColor: root.paints[root.mark.paint]
        PathSvg { path: root.mark.fill }
      }
    }
    LinearGradient {
      id: paint
      x1: 0; y1: 0; x2: 64; y2: 64
      GradientStop { position: 0; color: root.paints.lit }
      GradientStop { position: .5; color: root.paints.face }
      GradientStop { position: 1; color: root.paints.shadow }
    }
  }
}
