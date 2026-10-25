import QtQuick.Shapes

// Analytic edge coverage survives offscreen layers without MSAA attachments.
// Keep renderer selection here so every vector consumer has the same contract.
Shape {
  preferredRendererType: Shape.CurveRenderer
}
