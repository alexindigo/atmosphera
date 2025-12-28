import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.System
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  panelContent: Item {
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginM * 2)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: "device-analytics"
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

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      // Stats Grid + Bottom section
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: statsContainer.implicitHeight + (Style.marginM * 2)

        ColumnLayout {
          id: statsContainer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.marginM
          spacing: Style.marginM

          // Top row: 5 NCircleStat gauges
          RowLayout {
            id: topRow
            Layout.fillWidth: true
            spacing: Style.marginS

            // CPU Usage
            NCircleStat {
              ratio: SystemStatService.cpuUsage / 100
              icon: "cpu-usage"
              suffix: "%"
              flat: true
              fillColor: SystemStatService.cpuColor
              Layout.fillWidth: true
            }

            // CPU Temperature
            NCircleStat {
              ratio: SystemStatService.cpuTemp / 100
              icon: "cpu-temperature"
              suffix: "\u00B0"
              flat: true
              fillColor: SystemStatService.tempColor
              visible: SystemStatService.cpuTemp > 0
              Layout.fillWidth: true
            }

            // GPU Temperature
            NCircleStat {
              ratio: SystemStatService.gpuTemp / 100
              icon: "gpu-temperature"
              suffix: "\u00B0"
              flat: true
              fillColor: SystemStatService.gpuColor
              visible: SystemStatService.gpuAvailable
              Layout.fillWidth: true
            }

            // Memory Usage
            NCircleStat {
              ratio: SystemStatService.memPercent / 100
              icon: "memory"
              suffix: "%"
              flat: true
              fillColor: SystemStatService.memColor
              Layout.fillWidth: true
            }

            // Disk Usage
            NCircleStat {
              ratio: (SystemStatService.diskPercents["/"] ?? 0) / 100
              icon: "storage"
              suffix: "%"
              flat: true
              fillColor: SystemStatService.getDiskColor("/")
              Layout.fillWidth: true
            }
          }

          // Divider
          NDivider {
            Layout.fillWidth: true
          }

          // Bottom row: 2 NCircleStat (download/upload) + Detailed Stats
          RowLayout {
            id: bottomRow
            Layout.fillWidth: true
            spacing: Style.marginM

            // Download gauge
            NCircleStat {
              ratio: SystemStatService.rxRatio
              icon: "download-speed"
              suffix: "%"
              flat: true
              fillColor: Color.mPrimary
              Layout.preferredWidth: Math.round(80 * Style.uiScaleRatio)
            }

            // Upload gauge
            NCircleStat {
              ratio: SystemStatService.txRatio
              icon: "upload-speed"
              suffix: "%"
              flat: true
              fillColor: Color.mPrimary
              Layout.preferredWidth: Math.round(80 * Style.uiScaleRatio)
            }

            // Detailed Stats column
            ColumnLayout {
              id: detailsColumn
              Layout.fillWidth: true
              spacing: Style.marginS

              // Download speed
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "download-speed"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.download") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              // Upload speed
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "upload-speed"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.upload") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              // Memory details
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "memory"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.memory") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: SystemStatService.formatMemoryGb(SystemStatService.memGb)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              // Disk details
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: "storage"
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: I18n.tr("system-monitor.disk") + ":"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: {
                    const usedGb = SystemStatService.diskUsedGb["/"] || 0;
                    const sizeGb = SystemStatService.diskSizeGb["/"] || 0;
                    return `${usedGb.toFixed(1)}G / ${sizeGb.toFixed(1)}G`;
                  }
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
  }
}
