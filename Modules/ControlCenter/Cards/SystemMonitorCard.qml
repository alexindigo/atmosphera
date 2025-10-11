import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Unified system card: monitors CPU, temp, memory, disk
NBox {
  id: root

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginS * scaling

    ColumnLayout {
      anchors.centerIn: parent
      spacing: 0

      NCircleStat {
        value: SystemStatService.cpuUsage
        icon: "cpu-usage"
        flat: true
        contentScale: 0.8
        width: 70 * scaling
        height: 65 * scaling
        Layout.alignment: Qt.AlignHCenter
      }
      NCircleStat {
        value: SystemStatService.cpuTemp
        suffix: "°C"
        icon: "cpu-temperature"
        flat: true
        contentScale: 0.8
        width: 70 * scaling
        height: 65 * scaling
        Layout.alignment: Qt.AlignHCenter
      }
      NCircleStat {
        value: SystemStatService.memPercent
        icon: "memory"
        flat: true
        contentScale: 0.8
        width: 70 * scaling
        height: 65 * scaling
        Layout.alignment: Qt.AlignHCenter
      }
      NCircleStat {
        value: SystemStatService.diskPercent
        icon: "storage"
        flat: true
        contentScale: 0.8
        width: 70 * scaling
        height: 65 * scaling
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }
}
