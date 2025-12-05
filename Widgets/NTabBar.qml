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
  implicitHeight: Style.baseWidgetSize
  color: Color.mSurfaceVariant
  radius: Style.iRadiusS

  RowLayout {
    id: tabRow
    anchors.fill: parent
    anchors.margins: 0
    spacing: root.spacing
  }
}
