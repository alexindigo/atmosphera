import QtQuick
import qs.Commons
import qs.Services.Files

// One viewport interaction owner for every presentation. Geometry comes from
// the view; selection algebra comes from FileSelection. Touch keeps native flick.
Item {
  id: root
  required property Flickable viewport
  required property FileSelection selection
  required property var indexAt
  required property var intersectingIndices
  signal focusRequested
  signal activated(int index)
  readonly property bool dragging: drag.active
  property point _start: Qt.point(0, 0)
  property point _pointer: Qt.point(0, 0)
  readonly property point _end: Qt.point(Math.max(0, Math.min(width, _pointer.x)) + viewport.contentX,
    Math.max(0, Math.min(height, _pointer.y)) + viewport.contentY)
  readonly property rect bandRect: Qt.rect(Math.min(_start.x, _end.x), Math.min(_start.y, _end.y),
    Math.abs(_start.x - _end.x), Math.abs(_start.y - _end.y))
  clip: true

  function updateBand() {
    if (dragging)
      selection.updateBand(intersectingIndices(bandRect));
  }
  TapHandler {
    id: tap
    acceptedButtons: Qt.LeftButton
    onTapped: {
      root.focusRequested();
      var index = root.indexAt(point.position);
      if (index >= 0)
        root.selection.click(index, point.modifiers);
      else root.selection.background(point.modifiers);
    }
    onDoubleTapped: {
      var index = root.indexAt(point.position);
      if (point.modifiers === Qt.NoModifier && index >= 0)
        root.activated(index);
    }
  }
  DragHandler {
    id: drag
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    acceptedButtons: Qt.LeftButton
    enabled: root.selection.multiple && root.selection.browser.status !== "loading"
    onActiveChanged: {
      if (active) {
        root._pointer = centroid.position;
        root._start = Qt.point(centroid.pressPosition.x + root.viewport.contentX, centroid.pressPosition.y + root.viewport.contentY);
        root.selection.beginBand(centroid.modifiers, root.indexAt(centroid.pressPosition));
        root.focusRequested();
        root.updateBand();
      } else root.selection.endBand(root.indexAt(root._pointer));
    }
    onCentroidChanged: {
      if (active) {
        root._pointer = centroid.position;
        root.updateBand();
      }
    }
  }
  Timer {
    interval: 16
    running: root.dragging && root.visible && root.enabled
    repeat: true
    onTriggered: {
      var edge = Math.min(Style.margin2L, root.height / 4);
      var distance = root._pointer.y < edge ? root._pointer.y - edge
        : root._pointer.y > root.height - edge ? root._pointer.y - (root.height - edge) : 0;
      if (distance) {
        var start = root.viewport.originY;
        var end = start + Math.max(0, root.viewport.contentHeight - root.viewport.height);
        root.viewport.contentY = Math.max(start, Math.min(end, root.viewport.contentY
          + Math.max(-1, Math.min(1, distance / edge)) * Style.baseWidgetSize / 2));
        root.updateBand();
      }
    }
  }
  Rectangle {
    visible: root.dragging
    x: root.bandRect.x - root.viewport.contentX
    y: root.bandRect.y - root.viewport.contentY
    width: root.bandRect.width
    height: root.bandRect.height
    color: Qt.alpha(AtmoColor.mPrimary, .15)
    border.color: AtmoColor.mPrimary
    border.width: Style.borderS
  }
}
