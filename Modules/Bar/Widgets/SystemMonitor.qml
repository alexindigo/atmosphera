import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
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
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage

  anchors.centerIn: parent
  implicitWidth: isVertical ? Math.round(Style.capsuleHeight * scaling) : Math.round(mainGrid.implicitWidth + Style.marginM * 2 * scaling)
  implicitHeight: isVertical ? Math.round(mainGrid.implicitHeight + Style.marginM * 2 * scaling) : Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Color.mSurfaceVariant

  // Compact speed formatter for vertical bar display
  function formatCompactSpeed(bytesPerSecond) {
    if (!bytesPerSecond || bytesPerSecond <= 0)
      return "0"
    const units = ["", "k", "M", "G"]
    let value = bytesPerSecond
    let unitIndex = 0
    while (value >= 1024 && unitIndex < units.length - 1) {
      value = value / 1024.0
      unitIndex++
    }
    // Promote at ~100 of current unit (e.g., 100k -> ~0.1M shown as 0.1M or 0M if rounded)
    if (unitIndex < units.length - 1 && value >= 100) {
      value = value / 1024.0
      unitIndex++
    }
    const display = (value >= 10) ? Math.round(value).toString() : value.toFixed(1)
    return display + units[unitIndex]
  }

  GridLayout {
    id: mainGrid
    anchors.centerIn: parent

    // Dynamic layout based on bar orientation
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: isVertical ? -1 : 1
    columns: isVertical ? 1 : -1

    rowSpacing: isVertical ? (Style.marginS * scaling) : (Style.marginXS * scaling)
    columnSpacing: isVertical ? (Style.marginXS * scaling) : (Style.marginXS * scaling)

    // CPU Usage Component
    Item {
      Layout.preferredWidth: cpuUsageContent.implicitWidth
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuUsage

      GridLayout {
        id: cpuUsageContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NText {
          text: isVertical ? `${Math.round(SystemStatService.cpuUsage)}%` : `${SystemStatService.cpuUsage}%`
          font.family: Settings.data.ui.fontFixed
          font.pointSize: isVertical ? (Style.fontSizeXXS * scaling) : (Style.fontSizeXS * scaling)
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        NIcon {
          icon: "cpu-usage"
          font.pointSize: isVertical ? (Style.fontSizeS * scaling) : (Style.fontSizeM * scaling)
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }
      }
    }

    // CPU Temperature Component
    Item {
      Layout.preferredWidth: cpuTempContent.implicitWidth
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuTemp

      GridLayout {
        id: cpuTempContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NText {
          text: isVertical ? `${SystemStatService.cpuTemp}°` : `${SystemStatService.cpuTemp}°C`
          font.family: Settings.data.ui.fontFixed
          font.pointSize: isVertical ? (Style.fontSizeXXS * scaling) : (Style.fontSizeXS * scaling)
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        NIcon {
          icon: "cpu-temperature"
          font.pointSize: isVertical ? (Style.fontSizeXS * scaling) : (Style.fontSizeS * scaling)
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }
      }
    }

    // Memory Usage Component
    Item {
      Layout.preferredWidth: memoryContent.implicitWidth
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showMemoryUsage

      GridLayout {
        id: memoryContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NText {
          text: {
            if (showMemoryAsPercent) {
              return `${SystemStatService.memPercent}%`
            } else {
              return isVertical ? `${Math.round(SystemStatService.memGb)}G` : `${SystemStatService.memGb}G`
            }
          }
          font.family: Settings.data.ui.fontFixed
          font.pointSize: isVertical ? (Style.fontSizeXXS * scaling) : (Style.fontSizeXS * scaling)
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        NIcon {
          icon: "memory"
          font.pointSize: isVertical ? (Style.fontSizeS * scaling) : (Style.fontSizeM * scaling)
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }
      }
    }

    // Network Download Speed Component
    Item {
      Layout.preferredWidth: downloadContent.implicitWidth
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: downloadContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: isVertical ? (Style.marginXXS * scaling) : (Style.marginXS * scaling)

        NText {
          text: isVertical ? formatCompactSpeed(SystemStatService.rxSpeed) : SystemStatService.formatSpeed(SystemStatService.rxSpeed)
          font.family: Settings.data.ui.fontFixed
          font.pointSize: isVertical ? (Style.fontSizeXXS * scaling) : (Style.fontSizeXS * scaling)
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        NIcon {
          icon: "download-speed"
          font.pointSize: isVertical ? (Style.fontSizeS * scaling) : (Style.fontSizeM * scaling)
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }
      }
    }

    // Network Upload Speed Component
    Item {
      Layout.preferredWidth: uploadContent.implicitWidth
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: uploadContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: isVertical ? (Style.marginXXS * scaling) : (Style.marginXS * scaling)

        NText {
          text: isVertical ? formatCompactSpeed(SystemStatService.txSpeed) : SystemStatService.formatSpeed(SystemStatService.txSpeed)
          font.family: Settings.data.ui.fontFixed
          font.pointSize: isVertical ? (Style.fontSizeXXS * scaling) : (Style.fontSizeXS * scaling)
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        NIcon {
          icon: "upload-speed"
          font.pointSize: isVertical ? (Style.fontSizeS * scaling) : (Style.fontSizeM * scaling)
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }
      }
    }

    // Disk Usage Component (primary drive)
    Item {
      Layout.preferredWidth: diskContent.implicitWidth
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showDiskUsage

      GridLayout {
        id: diskContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: isVertical ? (Style.marginXXS * scaling) : (Style.marginXS * scaling)

        NText {
          text: `${SystemStatService.diskPercent}%`
          font.family: Settings.data.ui.fontFixed
          font.pointSize: isVertical ? (Style.fontSizeXXS * scaling) : (Style.fontSizeXS * scaling)
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
        }

        NIcon {
          icon: "storage"
          font.pointSize: isVertical ? (Style.fontSizeS * scaling) : (Style.fontSizeM * scaling)
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }
      }
    }
  }
}
