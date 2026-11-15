import QtQuick
import qs.Commons
import qs.Widgets

Rectangle {
  id: root
  signal resizeRequested(real dx, real dy)
  property point _last: Qt.point(0, 0)
  width: Style.baseWidgetSize * Style.uiScaleRatio
  height: width
  color: activeFocus ? Qt.alpha(AtmoColor.mPrimary, .15) : "transparent"
  activeFocusOnTab: true
  Accessible.role: Accessible.Grip
  Accessible.name: I18n.tr("widgets.file-picker.dialog-size")
  Accessible.focusable: true
  Keys.onLeftPressed: resizeRequested(-10 * Style.uiScaleRatio, 0)
  Keys.onRightPressed: resizeRequested(10 * Style.uiScaleRatio, 0)
  Keys.onUpPressed: resizeRequested(0, -10 * Style.uiScaleRatio)
  Keys.onDownPressed: resizeRequested(0, 10 * Style.uiScaleRatio)
  AtmoIcon {
    anchors.centerIn: parent
    icon: ({
             type: "svg",
             source: Qt.resolvedUrl("resize-grip.svg")
           })
    pointSize: Style.fontSizeS
    color: root.activeFocus ? AtmoColor.mPrimary : AtmoColor.mOnSurfaceVariant
  }
  HoverHandler {
    cursorShape: Qt.SizeFDiagCursor
  }
  DragHandler {
    id: drag
    target: null
    onActiveChanged: if (active) {
                       root._last = Qt.point(0, 0);
                       root.forceActiveFocus();
                     }
    onTranslationChanged: if (active) {
                            var delta = Qt.point(translation.x - root._last.x, translation.y - root._last.y);
                            root._last = translation;
                            root.resizeRequested(delta.x, delta.y);
                          }
  }
}
