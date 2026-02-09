import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Networking
import qs.Widgets

Item {
  id: root
  Layout.fillWidth: true
  // TBD: Implement Ethernet settings
  implicitHeight: placeholder.implicitHeight

  NBox {
    id: placeholder
    anchors.fill: parent
    implicitHeight: 100

    NText {
      anchors.centerIn: parent
      text: "Ethernet Settings - Coming Soon"
      color: Color.mOnSurfaceVariant
    }
  }
}
