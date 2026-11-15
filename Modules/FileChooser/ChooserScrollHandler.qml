import QtQuick

// Keep Qt's wheel/finger deltas, without Flickable's wheel-velocity easing.
// Touch dragging and native kinetic flicking still belong to the viewport.
WheelHandler {
  required property Flickable viewport
  required property real lineHeight
  property bool horizontal: false
  target: null
  enabled: viewport.visible
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  acceptedModifiers: Qt.NoModifier
  onWheel: event => {
    // Wayland also supplies pixelDelta for discrete mouse wheels. Gesture
    // phases distinguish those from finger/pixel scrolling without scaling it.
    var pixelDelta = horizontal && event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.pixelDelta.y;
    var angleDelta = horizontal && event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
    var pixels = event.phase !== Qt.NoScrollPhase && pixelDelta !== 0;
    var delta = pixels ? pixelDelta : angleDelta / 120 * Qt.styleHints.wheelScrollLines * lineHeight;
    if (delta === 0)
      return;
    viewport.cancelFlick();
    var start = horizontal ? viewport.originX : viewport.originY;
    var end = start + Math.max(0, horizontal ? viewport.contentWidth - viewport.width : viewport.contentHeight - viewport.height);
    if (horizontal)
      viewport.contentX = Math.max(start, Math.min(end, viewport.contentX - delta));
    else
      viewport.contentY = Math.max(start, Math.min(end, viewport.contentY - delta));
    event.accepted = true;
  }
}
