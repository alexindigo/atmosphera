import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Public properties
  property int currentIndex: 0
  property int spacing: Style.marginS
  default property alias content: tabRow.children

  // Styling
  Layout.fillWidth: true
  implicitHeight: Style.baseWidgetSize + (Style.marginM * 2)
  color: Color.mSurfaceVariant
  radius: Style.iRadiusS

  RowLayout {
    id: tabRow
    anchors.fill: parent
    anchors.topMargin: Style.marginM
    anchors.bottomMargin: Style.marginM
    anchors.leftMargin: Style.marginM
    anchors.rightMargin: Style.marginM
    spacing: root.spacing
  }
}
