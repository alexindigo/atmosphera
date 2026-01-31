import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  clip: true // Clip curves that overshoot bounds

  property var values: []
  property real minValue: 0
  property real maxValue: 100
  property bool autoScale: false
  property color color: Color.mPrimary
  property real strokeWidth: 2 * Style.uiScaleRatio
  property bool fill: true
  property real fillOpacity: 0.15

  readonly property bool hasData: values.length >= 2

  // Padding for bezier overshoot (percentage of range)
  readonly property real curvePadding: 0.08

  // Computed effective range for rendering (includes padding for bezier overshoot)
  readonly property real effectiveMin: {
    let min = minValue;
    let max = maxValue;
    if (autoScale && values && values.length > 0) {
      min = Math.min(...values);
      max = Math.max(...values);
    }
    let range = max - min;
    let padding = range * curvePadding;
    return min - padding;
  }
  readonly property real effectiveMax: {
    let min = minValue;
    let max = maxValue;
    if (autoScale && values && values.length > 0) {
      min = Math.min(...values);
      max = Math.max(...values);
    }
    let range = max - min;
    let padding = range * curvePadding;
    return max + padding;
  }

  // Convert a value to Y coordinate (no clamping - let bezier control points overshoot naturally)
  function valueToY(val) {
    let range = effectiveMax - effectiveMin;
    if (range <= 0)
      return height / 2;
    let normalized = (val - effectiveMin) / range;
    return height - normalized * height;
  }

  // Generate SVG path using monotone cubic interpolation (better for data visualization)
  readonly property string curvePath: {
    if (!values || values.length < 2 || width <= 0 || height <= 0)
      return "";

    const n = values.length;

    // Build array of points
    let points = [];
    for (let i = 0; i < n; i++) {
      points.push({
                    x: (i / (n - 1)) * width,
                    y: valueToY(values[i])
                  });
    }

    // For only 2 points, draw a line
    if (points.length === 2) {
      return `M ${points[0].x.toFixed(2)} ${points[0].y.toFixed(2)} L ${points[1].x.toFixed(2)} ${points[1].y.toFixed(2)}`;
    }

    // Calculate tangents using finite differences (monotone cubic)
    let tangents = [];
    for (let i = 0; i < points.length; i++) {
      if (i === 0) {
        tangents.push((points[1].y - points[0].y) / (points[1].x - points[0].x));
      } else if (i === points.length - 1) {
        tangents.push((points[i].y - points[i - 1].y) / (points[i].x - points[i - 1].x));
      } else {
        // Average of left and right slopes
        const left = (points[i].y - points[i - 1].y) / (points[i].x - points[i - 1].x);
        const right = (points[i + 1].y - points[i].y) / (points[i + 1].x - points[i].x);
        tangents.push((left + right) / 2);
      }
    }

    // Build the path
    let path = `M ${points[0].x.toFixed(2)} ${points[0].y.toFixed(2)}`;

    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[i];
      const p1 = points[i + 1];
      const dx = p1.x - p0.x;

      // Control points for cubic bezier
      const cp1x = p0.x + dx / 3;
      const cp1y = p0.y + tangents[i] * dx / 3;
      const cp2x = p1.x - dx / 3;
      const cp2y = p1.y - tangents[i + 1] * dx / 3;

      path += ` C ${cp1x.toFixed(2)},${cp1y.toFixed(2)} ${cp2x.toFixed(2)},${cp2y.toFixed(2)} ${p1.x.toFixed(2)},${p1.y.toFixed(2)}`;
    }

    return path;
  }

  // Path for the filled area (curve + bottom edge)
  readonly property string fillPath: {
    if (!curvePath || width <= 0 || height <= 0)
      return "";
    return curvePath + ` L ${width.toFixed(2)} ${height.toFixed(2)} L 0 ${height.toFixed(2)} Z`;
  }

  Shape {
    anchors.fill: parent
    layer.enabled: true
    layer.samples: 4
    antialiasing: true
    visible: root.hasData

    // Filled area under the curve
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: 0
        y1: 0
        x2: 0
        y2: root.height
        GradientStop {
          position: 0.0
          color: Qt.rgba(root.color.r, root.color.g, root.color.b, root.fillOpacity)
        }
        GradientStop {
          position: 1.0
          color: "transparent"
        }
      }
      PathSvg {
        path: root.fillPath
      }
    }

    // Stroke on top
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg {
        path: root.curvePath
      }
    }
  }
}
