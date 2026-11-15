import QtQuick
import qs.Commons

Rectangle {
  id: root
  required property string label
  signal resizeRequested(real delta)
  property real _last: 0
  width: Style.marginM
  color: activeFocus || drag.active ? Qt.alpha(AtmoColor.mPrimary, .15) : "transparent"
  activeFocusOnTab: true
  Accessible.role: Accessible.Splitter
  Accessible.name: label
  Accessible.focusable: true
  Accessible.onIncreaseAction: resizeRequested(10 * Style.uiScaleRatio)
  Accessible.onDecreaseAction: resizeRequested(-10 * Style.uiScaleRatio)
  Keys.onLeftPressed: resizeRequested(-10 * Style.uiScaleRatio)
  Keys.onRightPressed: resizeRequested(10 * Style.uiScaleRatio)
  Rectangle {
    anchors.centerIn: parent
    width: Style.borderS
    height: parent.height / 2
    color: root.activeFocus ? AtmoColor.mPrimary : AtmoColor.mOutline
  }
  HoverHandler {
    cursorShape: Qt.SplitHCursor
  }
  DragHandler {
    id: drag
    target: null
    yAxis.enabled: false
    onActiveChanged: if (active) {
                       root._last = 0;
                       root.forceActiveFocus();
                     }
    onTranslationChanged: {
      if (active) {
        var delta = translation.x - root._last;
        root._last = translation.x;
        root.resizeRequested(delta);
      }
    }
  }
}
