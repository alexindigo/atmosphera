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

  // History tracking
  property var history: []
  readonly property int maxHistory: 60 // 60 points at 1s = 1 minute of history

  implicitWidth: Math.round(240 * widgetScale)
  implicitHeight: Math.round(100 * widgetScale)
  width: implicitWidth
  height: implicitHeight

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      let val = 0;
      switch (root.statType) {
      case "CPU":
        val = SystemStatService.cpuUsage;
        break;
      case "GPU":
        val = SystemStatService.gpuTemp;
        break;
      case "Memory":
        val = SystemStatService.memPercent;
        break;
      case "Disk":
        val = SystemStatService.diskPercents[root.diskPath] || 0;
        break;
      case "Network":
        val = Math.max(SystemStatService.rxRatio, SystemStatService.txRatio) * 100;
        break;
      }

      let newHistory = root.history.slice();
      newHistory.push(val);
      if (newHistory.length > root.maxHistory) {
        newHistory.shift();
      }
      root.history = newHistory;
    }
  }

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
            return "gpu";
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
        text: {
          const lastVal = root.history.length > 0 ? root.history[root.history.length - 1] : 0;
          return Math.round(lastVal) + (root.statType === "GPU" ? "°C" : "%");
        }
        color: root.color
        pointSize: Style.fontSizeS * root.widgetScale
        font.weight: Style.fontWeightBold
        horizontalAlignment: Text.AlignHCenter
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
      maxValue: 100
      color: root.color
      fill: true
    }
  }
}
