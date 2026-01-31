import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.System
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  // Widget settings
  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["SystemStat"]
  readonly property string statType: (widgetData && widgetData.statType !== undefined) ? widgetData.statType : (widgetMetadata.statType !== undefined ? widgetMetadata.statType : "CPU")
  readonly property string diskPath: (widgetData && widgetData.diskPath !== undefined) ? widgetData.diskPath : "/"
  readonly property color color: (widgetData && widgetData.color !== undefined) ? widgetData.color : Color.mPrimary

  // History from service (2 minutes of data)
  readonly property var history: {
    switch (root.statType) {
    case "CPU":
      return SystemStatService.cpuHistory;
    case "GPU":
      return SystemStatService.gpuTempHistory;
    case "Memory":
      return SystemStatService.memHistory;
    case "Disk":
      return SystemStatService.diskHistories[root.diskPath] || [];
    case "Network":
      return SystemStatService.networkHistory;
    default:
      return [];
    }
  }

  // Current value from service
  readonly property real currentValue: {
    switch (root.statType) {
    case "CPU":
      return SystemStatService.cpuUsage;
    case "GPU":
      return SystemStatService.gpuTemp;
    case "Memory":
      return SystemStatService.memPercent;
    case "Disk":
      return SystemStatService.diskPercents[root.diskPath] || 0;
    case "Network":
      return Math.max(SystemStatService.rxRatio, SystemStatService.txRatio) * 100;
    default:
      return 0;
    }
  }

  implicitWidth: Math.round(240 * widgetScale)
  implicitHeight: Math.round(100 * widgetScale)
  width: implicitWidth
  height: implicitHeight

  RowLayout {
    anchors.fill: parent
    anchors.margins: Math.round(Style.marginL * widgetScale)
    spacing: Math.round(Style.marginL * widgetScale)

    ColumnLayout {
      Layout.alignment: Qt.AlignVCenter
      Layout.fillHeight: true
      Layout.preferredWidth: Math.round(64 * widgetScale)
      spacing: Style.marginXS * root.widgetScale

      NIcon {
        Layout.alignment: Qt.AlignHCenter
        icon: {
          switch (root.statType) {
          case "CPU":
            return "cpu-usage";
          case "GPU":
            return "gpu-temperature";
          case "Memory":
            return "memory";
          case "Disk":
            return "storage";
          case "Network":
            return "network";
          default:
            return "help";
          }
        }
        color: root.color
        pointSize: Style.fontSizeXL * root.widgetScale
      }

      NText {
        Layout.alignment: Qt.AlignHCenter
        text: Math.round(root.currentValue) + (root.statType === "GPU" ? "°C" : "%")
        color: root.color
        pointSize: Style.fontSizeS * root.widgetScale
        font.weight: Style.fontWeightBold
        horizontalAlignment: Text.AlignHCenter
      }

      NText {
        Layout.alignment: Qt.AlignHCenter
        visible: root.statType === "CPU"
        text: SystemStatService.cpuFreq
        color: root.color
        pointSize: Style.fontSizeXXS * root.widgetScale
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.8
      }

      NText {
        Layout.alignment: Qt.AlignHCenter
        visible: root.statType === "Disk" && root.diskPath !== "/"
        text: root.diskPath
        color: root.color
        pointSize: Style.fontSizeXXS * root.widgetScale
        elide: Text.ElideMiddle
        Layout.maximumWidth: Math.round(56 * widgetScale)
        opacity: 0.8
      }
    }

    NGraph {
      Layout.fillWidth: true
      Layout.fillHeight: true
      values: root.history
      autoScale: root.statType === "GPU"
      maxValue: 100
      color: root.color
      fill: true
    }
  }
}
