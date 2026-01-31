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

  // History from service
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
      return SystemStatService.rxSpeedHistory;
    default:
      return [];
    }
  }

  // Secondary history for Network (Tx)
  readonly property var history2: root.statType === "Network" ? SystemStatService.txSpeedHistory : []

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
        visible: root.statType !== "Network"
        text: Math.round(root.currentValue) + (root.statType === "GPU" ? "°C" : "%")
        color: root.color
        pointSize: Style.fontSizeS * root.widgetScale
        font.weight: Style.fontWeightBold
        horizontalAlignment: Text.AlignHCenter
      }

      // Network: show Rx speed
      NText {
        Layout.alignment: Qt.AlignHCenter
        visible: root.statType === "Network"
        text: "↓ " + SystemStatService.formatSpeed(SystemStatService.rxSpeed)
        color: root.color
        pointSize: Style.fontSizeXXS * root.widgetScale
        font.weight: Style.fontWeightBold
        horizontalAlignment: Text.AlignHCenter
      }

      // Network: show Tx speed
      NText {
        Layout.alignment: Qt.AlignHCenter
        visible: root.statType === "Network"
        text: "↑ " + SystemStatService.formatSpeed(SystemStatService.txSpeed)
        color: Color.mError
        pointSize: Style.fontSizeXXS * root.widgetScale
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
      values2: root.history2
      minValue: root.statType === "GPU" ? SystemStatService.gpuTempHistoryMin : 0
      maxValue: {
        switch (root.statType) {
        case "CPU":
          return Math.max(SystemStatService.cpuHistoryMax, 1);
        case "GPU":
          return Math.max(SystemStatService.gpuTempHistoryMax, 1);
        case "Memory":
          return Math.max(SystemStatService.memHistoryMax, 1);
        case "Network":
          return Math.max(SystemStatService.rxMaxSpeed, 1);
        default:
          return 100;
        }
      }
      // Secondary line (TX) has its own scale
      minValue2: minValue
      maxValue2: root.statType === "Network" ? Math.max(SystemStatService.txMaxSpeed, 1) : maxValue
      color: root.color
      color2: Color.mError
      fill: true
    }
  }
}
