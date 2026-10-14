import QtQuick
import qs.Commons
import qs.Widgets

// Shown in place of a plugin piece that could not be loaded (shared-loader
// design, 3.3). The caller sets the square size.
Item {
  id: root

  property real size: Style.baseWidgetSize

  implicitWidth: size
  implicitHeight: size
  opacity: 0.5

  AtmoIcon {
    anchors.centerIn: parent
    icon: "puzzle-off"
    color: AtmoColor.mOnSurfaceVariant
  }
}
