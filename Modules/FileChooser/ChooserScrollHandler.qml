import QtQuick

// Keep Qt's wheel/finger deltas, without Flickable's wheel-velocity easing.
// Touch dragging and native kinetic flicking still belong to the viewport.
WheelHandler {
  required property Flickable viewport
  required property real lineHeight
  target: null
  enabled: viewport.visible
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  acceptedModifiers: Qt.NoModifier
  onWheel: event => {
    // Wayland also supplies pixelDelta for discrete mouse wheels. Gesture
    // phases distinguish those from finger/pixel scrolling without scaling it.
    var pixels = event.phase !== Qt.NoScrollPhase && event.pixelDelta.y !== 0;
    var delta = pixels ? event.pixelDelta.y : event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * lineHeight;
    if (delta === 0)
      return;
    viewport.cancelFlick();
    var start = viewport.originY;
    var end = start + Math.max(0, viewport.contentHeight - viewport.height);
    viewport.contentY = Math.max(start, Math.min(end, viewport.contentY - delta));
    event.accepted = true;
  }
}
