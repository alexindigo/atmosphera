import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

// Unified system card: monitors CPU, temp, memory, disk
NBox {
  id: root

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginS

    property int widgetHeight: Math.round(65 * Style.uiScaleRatio)

    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.marginXS

      NCircleStat {
        ratio: SystemStatService.cpuUsage / 100
        icon: "cpu-usage"
        flat: true
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.cpuColor
        tooltipText: I18n.tr("system-monitor.cpu-usage") + `: ${Math.round(SystemStatService.cpuUsage)}%`
      }
      NCircleStat {
        ratio: SystemStatService.cpuTemp / 100
        suffix: "°C"
        icon: "cpu-temperature"
        flat: true
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.tempColor
        tooltipText: I18n.tr("system-monitor.cpu-temp") + `: ${Math.round(SystemStatService.cpuTemp)}°C`
      }
      NCircleStat {
        ratio: SystemStatService.memPercent / 100
        icon: "memory"
        flat: true
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.memColor
        tooltipText: I18n.tr("system-monitor.memory") + `: ${Math.round(SystemStatService.memPercent)}%`
      }
      NCircleStat {
        readonly property string diskPath: Settings.data.systemMonitor.diskPath || "/"
        ratio: (SystemStatService.diskPercents[diskPath] ?? 0) / 100
        icon: "storage"
        flat: true
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.getDiskColor(diskPath)
        tooltipText: I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[diskPath] || 0}%`
      }
    }
  }
}
