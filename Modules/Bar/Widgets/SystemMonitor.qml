import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string barPosition: Settings.data.bar.position

  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage

  implicitWidth: backgroundContainer.width
  implicitHeight: backgroundContainer.height

  Rectangle {
    id: backgroundContainer
    anchors.centerIn: parent
    width: (barPosition === "left" || barPosition === "right") ? Math.round(Style.capsuleHeight * scaling) : Math.round(horizontalLayout.implicitWidth + Style.marginS * 2 * scaling)
    height: (barPosition === "left" || barPosition === "right") ? Math.round(verticalLayout.implicitHeight + Style.marginS * 2 * scaling) : Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    // Horizontal layout for top/bottom bars
    RowLayout {
      id: horizontalLayout
      anchors.centerIn: parent
      anchors.leftMargin: Style.marginM * scaling
      anchors.rightMargin: Style.marginM * scaling
      spacing: Style.marginXS * scaling
      visible: barPosition === "top" || barPosition === "bottom"

      // CPU Usage Component
      Item {
        Layout.preferredWidth: cpuUsageRow.implicitWidth
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: showCpuUsage

        RowLayout {
          id: cpuUsageRow
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "cpu-usage"
            font.pointSize: Style.fontSizeM * scaling
            Layout.alignment: Qt.AlignVCenter
          }

          NText {
            text: `${SystemStatService.cpuUsage}%`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }

      // CPU Temperature Component
      Item {
        Layout.preferredWidth: cpuTempRow.implicitWidth
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: showCpuTemp

        RowLayout {
          id: cpuTempRow
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "cpu-temperature"
            // Fire is so tall, we need to make it smaller
            font.pointSize: Style.fontSizeS * scaling
            Layout.alignment: Qt.AlignVCenter
          }

          NText {
            text: `${SystemStatService.cpuTemp}°C`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }

      // Memory Usage Component
      Item {
        Layout.preferredWidth: memoryUsageRow.implicitWidth
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: showMemoryUsage

        RowLayout {
          id: memoryUsageRow
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "memory"
            font.pointSize: Style.fontSizeM * scaling
            Layout.alignment: Qt.AlignVCenter
          }

          NText {
            text: showMemoryAsPercent ? `${SystemStatService.memPercent}%` : `${SystemStatService.memGb}G`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }

      // Network Download Speed Component
      Item {
        Layout.preferredWidth: networkDownloadRow.implicitWidth
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: showNetworkStats

        RowLayout {
          id: networkDownloadRow
          anchors.centerIn: parent
          spacing: Style.marginXS * scaling

          NIcon {
            icon: "download-speed"
            font.pointSize: Style.fontSizeM * scaling
            Layout.alignment: Qt.AlignVCenter
          }

          NText {
            text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }

      // Network Upload Speed Component
      Item {
        Layout.preferredWidth: networkUploadRow.implicitWidth
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: showNetworkStats

        RowLayout {
          id: networkUploadRow
          anchors.centerIn: parent
          spacing: Style.marginXS * scaling

          NIcon {
            icon: "upload-speed"
            font.pointSize: Style.fontSizeM * scaling
            Layout.alignment: Qt.AlignVCenter
          }

          NText {
            text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }

      // Disk Usage Component (primary drive)
      Item {
        Layout.preferredWidth: diskUsageRow.implicitWidth
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: showDiskUsage

        RowLayout {
          id: diskUsageRow
          anchors.centerIn: parent
          spacing: Style.marginXS * scaling

          NIcon {
            icon: "storage"
            font.pointSize: Style.fontSizeM * scaling
            Layout.alignment: Qt.AlignVCenter
          }

          NText {
            text: `${SystemStatService.diskPercent}%`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }
    }

    // Vertical layout for left/right bars
    ColumnLayout {
      id: verticalLayout
      anchors.centerIn: parent
      anchors.topMargin: Style.marginS * scaling
      anchors.bottomMargin: Style.marginS * scaling
      width: Math.round(28 * scaling)
      spacing: Style.marginS * scaling
      visible: barPosition === "left" || barPosition === "right"

      // CPU Usage Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(28 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showCpuUsage

        Column {
          id: cpuUsageRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NText {
            text: `${Math.round(SystemStatService.cpuUsage)}%`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }

          NIcon {
            icon: "cpu-usage"
            font.pointSize: Style.fontSizeS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }

      // CPU Temperature Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(28 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showCpuTemp

        Column {
          id: cpuTempRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NText {
            text: `${SystemStatService.cpuTemp}°`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }

          NIcon {
            icon: "cpu-temperature"
            // Fire is so tall, we need to make it smaller
            font.pointSize: Style.fontSizeXS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }

      // Memory Usage Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(28 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showMemoryUsage

        Column {
          id: memoryUsageRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NText {
            text: showMemoryAsPercent ? `${SystemStatService.memPercent}%` : `${Math.round(SystemStatService.memGb)}G`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }

          NIcon {
            icon: "memory"
            font.pointSize: Style.fontSizeS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }

      // Network Download Speed Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(28 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showNetworkStats

        Column {
          id: networkDownloadRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "download-speed"
            font.pointSize: Style.fontSizeS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }

          NText {
            text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }
        }
      }

      // Network Upload Speed Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(28 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showNetworkStats

        Column {
          id: networkUploadRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "upload-speed"
            font.pointSize: Style.fontSizeS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }

          NText {
            text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }
        }
      }

      // Disk Usage Component (primary drive)
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(28 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showDiskUsage

        ColumnLayout {
          id: diskUsageRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "storage"
            font.pointSize: Style.fontSizeS * scaling
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: `${SystemStatService.diskPercent}%`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }
        }
      }
    }
  }
}
