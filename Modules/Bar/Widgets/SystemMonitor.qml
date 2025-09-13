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
  property string barPosition: "top"

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

  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage

  implicitHeight: (barPosition === "left" || barPosition === "right") ? calculatedVerticalHeight() : Math.round(Style.barHeight * scaling)
  implicitWidth: (barPosition === "left" || barPosition === "right") ? Math.round(Style.capsuleHeight * scaling) : calculatedHorizontalWidth()

  function calculatedVerticalHeight() {
    let total = 0
    let visibleCount = 0

    if (showCpuUsage)
      visibleCount++
    if (showCpuTemp)
      visibleCount++
    if (showMemoryUsage)
      visibleCount++
    if (showNetworkStats)
      visibleCount += 2 // download + upload
    if (showDiskUsage)
      visibleCount++

    total = visibleCount * Math.round(Style.capsuleHeight * scaling)
    total += Math.max(visibleCount - 1, 0) * Style.marginS * scaling
    total += Style.marginM * scaling * 2 // padding

    return total
  }

  function calculatedHorizontalWidth() {
    let total = Style.marginM * scaling * 2 // base padding

    if (showCpuUsage) {
      // Icon + "99%" text
      total += Style.fontSizeM * scaling * 1.2 + // icon
          Style.fontSizeXS * scaling * 2.5 + // text (~3 chars)
          2 * scaling // spacing
    }

    if (showCpuTemp) {
      // Icon + "85°C" text
      total += Style.fontSizeS * scaling * 1.2 + // smaller fire icon
          Style.fontSizeXS * scaling * 3.5 + // text (~4 chars)
          2 * scaling // spacing
    }

    if (showMemoryUsage) {
      // Icon + "16G" or "85%" text
      total += Style.fontSizeM * scaling * 1.2 + // icon
          Style.fontSizeXS * scaling * 3 + // text (~3-4 chars)
          2 * scaling // spacing
    }

    if (showNetworkStats) {
      // Download: icon + "1.2M" text
      total += Style.fontSizeM * scaling * 1.2 + // icon
          Style.fontSizeXS * scaling * 3.5 + // text
          Style.marginXS * scaling + 2 * scaling // spacing

      // Upload: icon + "256K" text
      total += Style.fontSizeM * scaling * 1.2 + // icon
          Style.fontSizeXS * scaling * 3.5 + // text
          Style.marginXS * scaling + 2 * scaling // spacing
    }

    if (showDiskUsage) {
      // Icon + "75%" text
      total += Style.fontSizeM * scaling * 1.2 + // icon
          Style.fontSizeXS * scaling * 3 + // text (~3 chars)
          Style.marginXS * scaling + 2 * scaling // spacing
    }

    // Add spacing between visible components
    let visibleCount = 0
    if (showCpuUsage)
      visibleCount++
    if (showCpuTemp)
      visibleCount++
    if (showMemoryUsage)
      visibleCount++
    if (showNetworkStats)
      visibleCount += 2
    if (showDiskUsage)
      visibleCount++

    if (visibleCount > 1) {
      total += (visibleCount - 1) * Style.marginXS * scaling
    }

    // Add extra margin for spacing between widgets in the bar
    total += Style.marginM * scaling * 2 // widget-to-widget spacing

    return Math.max(total, Style.capsuleHeight * scaling)
  }

  Rectangle {
    id: backgroundContainer
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: (barPosition === "left" || barPosition === "right") ? Math.round(Style.capsuleHeight * scaling) : calculatedHorizontalWidth()
    height: (barPosition === "left" || barPosition === "right") ? parent.height : Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    // Horizontal layout for top/bottom bars
    RowLayout {
      id: horizontalLayout
      anchors.centerIn: parent
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
          spacing: 2 * scaling

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
          spacing: 2 * scaling

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
          spacing: 2 * scaling

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
      width: Math.round(32 * scaling)
      height: parent.height - Style.marginM * scaling * 2
      spacing: Style.marginS * scaling
      visible: barPosition === "left" || barPosition === "right"

      // CPU Usage Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(32 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showCpuUsage

        Column {
          id: cpuUsageRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "cpu-usage"
            font.pointSize: Style.fontSizeS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }

          NText {
            text: `${SystemStatService.cpuUsage}%`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling * 0.8
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }
        }
      }

      // CPU Temperature Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(32 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showCpuTemp

        Column {
          id: cpuTempRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "cpu-temperature"
            // Fire is so tall, we need to make it smaller
            font.pointSize: Style.fontSizeXS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }

          NText {
            text: `${SystemStatService.cpuTemp}°C`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling * 0.8
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }
        }
      }

      // Memory Usage Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(32 * scaling)
        Layout.alignment: Qt.AlignHCenter
        visible: showMemoryUsage

        Column {
          id: memoryUsageRowVertical
          anchors.centerIn: parent
          spacing: Style.marginXXS * scaling

          NIcon {
            icon: "memory"
            font.pointSize: Style.fontSizeS * scaling
            anchors.horizontalCenter: parent.horizontalCenter
          }

          NText {
            text: showMemoryAsPercent ? `${SystemStatService.memPercent}%` : `${SystemStatService.memGb}G`
            font.family: Settings.data.ui.fontFixed
            font.pointSize: Style.fontSizeXXS * scaling * 0.8
            font.weight: Style.fontWeightMedium
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            color: Color.mPrimary
          }
        }
      }

      // Network Download Speed Component
      Item {
        Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
        Layout.preferredWidth: Math.round(32 * scaling)
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
            font.pointSize: Style.fontSizeXXS * scaling * 0.8
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
        Layout.preferredWidth: Math.round(32 * scaling)
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
            font.pointSize: Style.fontSizeXXS * scaling * 0.8
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
        Layout.preferredWidth: Math.round(32 * scaling)
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
            font.pointSize: Style.fontSizeXXS * scaling * 0.8
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
