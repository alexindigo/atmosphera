import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.System
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  Component.onCompleted: SystemStatService.registerComponent("panel-systemstats")
  Component.onDestruction: SystemStatService.unregisterComponent("panel-systemstats")

  preferredWidth: Math.round(440 * Style.uiScaleRatio)

  panelContent: Item {
    id: panelContent
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.margin2L
    readonly property real cardHeight: 90 * Style.uiScaleRatio

    // Get diskPath from bar's SystemMonitor widget if available, otherwise use "/"
    readonly property string diskPath: {
      const sysMonWidget = BarService.lookupWidget("SystemMonitor");
      if (sysMonWidget && sysMonWidget.diskPath) {
        return sysMonWidget.diskPath;
      }
      return "/";
    }

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + Style.margin2M

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          AtmoIcon {
            icon: Icon.systemStats
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("system-monitor.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          AtmoIconButton {
            icon: Icon.close
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      // CPU Card (dual-line: usage % + temperature °C)
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: panelContent.cardHeight

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginS
          anchors.bottomMargin: Style.radiusM * 0.5
          spacing: Style.marginXS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            AtmoIcon {
              icon: Icon.cpuUsage
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
            }

            NText {
              text: `${Math.round(SystemStatService.cpuUsage)}% (${SystemStatService.cpuFreq.replace(/[^0-9.]/g, "")} GHz)`
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
              font.family: Settings.data.ui.fontFixed
            }

            AtmoIcon {
              icon: Icon.cpuTemperature
              pointSize: Style.fontSizeXS
              color: Color.mSecondary
            }

            NText {
              text: `${Math.round(SystemStatService.cpuTemp)}°C`
              pointSize: Style.fontSizeXS
              color: Color.mSecondary
              font.family: Settings.data.ui.fontFixed
              Layout.rightMargin: Style.marginS
            }

            Item {
              Layout.fillWidth: true
            }

            NText {
              text: I18n.tr("system-monitor.cpu-usage")
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }

          NGraph {
            Layout.fillWidth: true
            Layout.fillHeight: true
            values: SystemStatService.cpuHistory
            values2: SystemStatService.cpuTempHistory
            minValue: 0
            maxValue: 100
            minValue2: Math.max(SystemStatService.cpuTempHistoryMin - 5, 0)
            maxValue2: Math.max(SystemStatService.cpuTempHistoryMax + 5, 1)
            color: Color.mPrimary
            color2: Color.mSecondary
            strokeWidth: Math.max(1, Style.uiScaleRatio)
            fill: true
            fillOpacity: 0.15
            updateInterval: SystemStatService.cpuUsageIntervalMs
          }
        }
      }

      // Memory Card (single-line + optional swap indicator)
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: panelContent.cardHeight

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginS
          anchors.bottomMargin: Style.radiusM * 0.5
          spacing: Style.marginXS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            AtmoIcon {
              icon: Icon.systemMemory
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
            }

            NText {
              text: `${Math.round(SystemStatService.memPercent)}% (${(SystemStatService.memGb).toFixed(1)} GiB)`
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
              font.family: Settings.data.ui.fontFixed
            }

            Item {
              Layout.fillWidth: true
            }

            NText {
              text: I18n.tr("common.memory")
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }

          NGraph {
            Layout.fillWidth: true
            Layout.fillHeight: true
            values: SystemStatService.memHistory
            minValue: 0
            maxValue: 100
            color: Color.mPrimary
            strokeWidth: Math.max(1, Style.uiScaleRatio)
            fill: true
            fillOpacity: 0.15
            updateInterval: SystemStatService.memIntervalMs
          }
        }
      }

      // Network Card (dual-line: RX + TX speeds)
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: panelContent.cardHeight

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginS
          anchors.bottomMargin: Style.radiusM * 0.5
          spacing: Style.marginXS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            AtmoIcon {
              icon: Icon.networkDownload
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
            }

            NText {
              text: SystemStatService.formatSpeed(SystemStatService.rxSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2") + "/s"
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
              font.family: Settings.data.ui.fontFixed
              Layout.rightMargin: Style.marginS
            }

            AtmoIcon {
              icon: Icon.networkUpload
              pointSize: Style.fontSizeXS
              color: Color.mSecondary
            }

            NText {
              text: SystemStatService.formatSpeed(SystemStatService.txSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2") + "/s"
              pointSize: Style.fontSizeXS
              color: Color.mSecondary
              font.family: Settings.data.ui.fontFixed
            }

            Item {
              Layout.fillWidth: true
            }

            NText {
              text: I18n.tr("common.network")
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }

          NGraph {
            Layout.fillWidth: true
            Layout.fillHeight: true
            values: SystemStatService.rxSpeedHistory
            values2: SystemStatService.txSpeedHistory
            minValue: 0
            maxValue: SystemStatService.rxMaxSpeed
            minValue2: 0
            maxValue2: SystemStatService.txMaxSpeed
            color: Color.mPrimary
            color2: Color.mSecondary
            strokeWidth: Math.max(1, Style.uiScaleRatio)
            fill: true
            fillOpacity: 0.15
            updateInterval: SystemStatService.networkIntervalMs
            animateScale: true
          }
        }
      }

      // Detailed Stats section
      NBox {
        Layout.fillWidth: true
        implicitHeight: detailsColumn.implicitHeight + Style.margin2M

        ColumnLayout {
          id: detailsColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.marginM
          spacing: Style.marginXS

          // Load Average
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: SystemStatService.nproc > 0

            AtmoIcon {
              icon: Icon.cpuUsage
              pointSize: Style.fontSizeM
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("system-monitor.load-average") + ":"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: `${SystemStatService.loadAvg1.toFixed(2)} • ${SystemStatService.loadAvg5.toFixed(2)} • ${SystemStatService.loadAvg15.toFixed(2)}`
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
            }
          }

          // GPU Temperature (only if available)
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: SystemStatService.gpuAvailable

            AtmoIcon {
              icon: Icon.gpuTemperature
              pointSize: Style.fontSizeM
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("system-monitor.gpu-temp") + ":"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: `${Math.round(SystemStatService.gpuTemp)}°C`
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
            }
          }

          // Hottest CPU core (coretemp per-core readings)
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: SystemStatService.hottestCoreTemp > 0

            AtmoIcon {
              icon: Icon.cpuTemperature
              pointSize: Style.fontSizeM
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("system-monitor.cpu-hottest-core") + ":"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: `${SystemStatService.hottestCoreTemp}°C`
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
            }
          }

          // Fan speed
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: SystemStatService.fanRpm > 0

            AtmoIcon {
              icon: Icon.fan
              pointSize: Style.fontSizeM
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("system-monitor.fan-speed") + ":"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: `${SystemStatService.fanRpm} RPM`
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
            }
          }

          // Extra sensors (DDR, EC, NVMe, etc.) — skip CPU/GPU, shown above
          Repeater {
            model: SystemStatService.sensors.filter(s => s.temp > 0 && s.chip !== "coretemp" && s.chip !== "amdgpu" && s.chip !== "xe")

            delegate: RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              required property var modelData

              AtmoIcon {
                icon: Icon.cpuTemperature
                pointSize: Style.fontSizeM
                color: Color.mPrimary
              }

              NText {
                text: (modelData.label || modelData.chip) + ":"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              NText {
                text: `${modelData.temp}°C` + (modelData.crit > 0 ? ` / ${modelData.crit}°C` : "")
                pointSize: Style.fontSizeXS
                color: modelData.crit > 0 && modelData.temp >= modelData.crit - Settings.data.hardwareHealth.warnOffsetC ? Color.mError : Color.mOnSurface
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          // Disk usage
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            AtmoIcon {
              icon: Icon.systemStorage
              pointSize: Style.fontSizeM
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("system-monitor.disk") + ":"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: {
                const usedGb = SystemStatService.diskUsedGb[panelContent.diskPath] || 0;
                const sizeGb = SystemStatService.diskSizeGb[panelContent.diskPath] || 0;
                const percent = SystemStatService.diskPercents[panelContent.diskPath] || 0;
                return `${percent}% (${usedGb.toFixed(1)} / ${sizeGb.toFixed(1)} GB)`;
              }
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideMiddle
            }
          }

          // Swap details (only visible if swap is enabled)
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: SystemStatService.swapTotalGb > 0

            AtmoIcon {
              icon: Icon.systemSwap
              pointSize: Style.fontSizeM
              color: Color.mPrimary
            }

            NText {
              text: I18n.tr("bar.system-monitor.swap-usage-label") + ":"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: `${(SystemStatService.swapGb).toFixed(1)} / ${(SystemStatService.swapTotalGb).toFixed(1)} GiB`
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }
    }
  }
}
