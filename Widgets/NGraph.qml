import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  property var values: []
  property real maxValue: 100
  property color color: Color.mPrimary
  property real strokeWidth: 2 * Style.uiScaleRatio
  property bool fill: true
  property real fillOpacity: 0.15
  property bool smooth: true

  readonly property bool hasData: values.length >= 2

  // Internal values for continuous temporal smoothing
  property var smoothValues: []

  Timer {
    interval: 16
    running: root.smooth && root.hasData
    repeat: true
    onTriggered: {
      if (!root.values || root.values.length === 0)
        return;

      // Initialize if needed
      if (root.smoothValues.length !== root.values.length) {
        root.smoothValues = root.values.slice();
        return;
      }

      let newValues = [];
      let updated = false;
      const lerpFactor = 0.10; // Balanced for responsiveness and liquid motion

      for (let i = 0; i < root.values.length; i++) {
        let diff = root.values[i] - root.smoothValues[i];
        if (Math.abs(diff) < 0.01) {
          newValues.push(root.values[i]);
        } else {
          newValues.push(root.smoothValues[i] + diff * lerpFactor);
          updated = true;
        }
      }
      if (updated)
        root.smoothValues = newValues;
    }
  }

  // Generate the SVG path string for a smooth curve
  readonly property string curvePath: {
    let rawSource = root.smooth ? root.smoothValues : root.values;
    if (!rawSource || rawSource.length < 2)
      return "";

    // Sample to 7 stable points for an ultra-broad, sweeping look
    const targetPoints = 7;
    let source = [];
    for (let i = 0; i < targetPoints; i++) {
      let exactIdx = i * (rawSource.length - 1) / (targetPoints - 1);
      let i1 = Math.floor(exactIdx);
      let i2 = Math.ceil(exactIdx);
      let t = exactIdx - i1;
      source.push(rawSource[i1] * (1 - t) + (rawSource[i2] ?? rawSource[i1]) * t);
    }

    let n = source.length;
    let path = `M 0 ${getY(0, source)}`;

    // Standard tension for the most natural "sweeping" look
    const tension = 0.5;
    const k = (1 - tension) / 3;

    for (let i = 0; i < n - 1; i++) {
      let x1 = (i / (n - 1)) * root.width;
      let y1 = getY(i, source);
      let x2 = ((i + 1) / (n - 1)) * root.width;
      let y2 = getY(i + 1, source);

      // Control points for Centripetal Catmull-Rom style spline
      let y0 = (i === 0) ? (2 * y1 - y2) : getY(i - 1, source);
      let x0 = ((i - 1) / (n - 1)) * root.width;

      let y3 = (i + 2 >= n) ? (2 * y2 - y1) : getY(i + 2, source);
      let x3 = ((i + 2) / (n - 1)) * root.width;

      let cp1x = x1 + (x2 - x0) * k;
      let cp1y = y1 + (y2 - y0) * k;
      let cp2x = x2 - (x3 - x1) * k;
      let cp2y = y2 - (y3 - y1) * k;

      path += ` C ${cp1x.toFixed(2)},${cp1y.toFixed(2)} ${cp2x.toFixed(2)},${cp2y.toFixed(2)} ${x2.toFixed(2)},${y2.toFixed(2)}`;
    }
    return path;
  }

  Shape {
    id: shape
    anchors.fill: parent
    antialiasing: true
    visible: root.hasData

    ShapePath {
      id: strokePath
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap

      PathSvg {
        path: root.curvePath
      }
    }

    ShapePath {
      id: fillPath
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
        path: root.curvePath + ` L ${root.width} ${root.height} L 0 ${root.height} Z`
      }
    }
  }

  function getY(idx, source) {
    if (!source || source.length === 0)
      return root.height;
    let i = Math.max(0, Math.min(source.length - 1, idx));
    return root.height - (Math.max(0, Math.min(root.maxValue, source[i])) / root.maxValue) * root.height;
  }
}
