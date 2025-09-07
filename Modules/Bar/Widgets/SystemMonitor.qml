import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

RowLayout {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetSettings: {
    var section = barSection.replace("Section", "").toLowerCase()
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool userShowCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showCpuUsage
  readonly property bool userShowCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showCpuTemp
  readonly property bool userShowMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showMemoryUsage
  readonly property bool userShowNetworkStats: (widgetSettings.showNetworkStats
                                                !== undefined) ? widgetSettings.showNetworkStats : ((Settings.data.bar.showNetworkStats !== undefined) ? Settings.data.bar.showNetworkStats : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showNetworkStats)

  Component.onCompleted: {
    try {
      var section = barSection.replace("Section", "").toLowerCase()
      if (section && sectionWidgetIndex >= 0) {
        var widgets = Settings.data.bar.widgets[section]
        if (widgets && sectionWidgetIndex < widgets.length) {
          if (widgets[sectionWidgetIndex].showNetworkStats === undefined
              && Settings.data.bar.showNetworkStats !== undefined) {
            widgets[sectionWidgetIndex].showNetworkStats = Settings.data.bar.showNetworkStats
          }
        }
      }
    } catch (e) {

    }
  }

  Layout.alignment: Qt.AlignVCenter
  spacing: Style.marginS * scaling

  Rectangle {
    Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
    Layout.preferredWidth: mainLayout.implicitWidth + Style.marginM * scaling * 2
    Layout.alignment: Qt.AlignVCenter

    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    RowLayout {
      id: mainLayout
      anchors.fill: parent
      anchors.leftMargin: Style.marginS * scaling
      anchors.rightMargin: Style.marginS * scaling
      spacing: Style.marginS * scaling

      // CPU Usage Component
      RowLayout {
        id: cpuUsageLayout
        spacing: Style.marginXS * scaling
        Layout.alignment: Qt.AlignVCenter
        visible: userShowCpuUsage

        NIcon {
          id: cpuUsageIcon
          text: "speed"
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          id: cpuUsageText
          text: `${SystemStatService.cpuUsage}%`
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
        }
      }

      // CPU Temperature Component
      RowLayout {
        id: cpuTempLayout
        // spacing is thin here to compensate for the vertical thermometer icon
        spacing: Style.marginXXS * scaling
        Layout.alignment: Qt.AlignVCenter
        visible: userShowCpuTemp

        NIcon {
          text: "thermometer"
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: `${SystemStatService.cpuTemp}°C`
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
        }
      }

      // Memory Usage Component
      RowLayout {
        id: memoryUsageLayout
        spacing: Style.marginXS * scaling
        Layout.alignment: Qt.AlignVCenter
        visible: userShowMemoryUsage

        NIcon {
          text: "memory"
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: `${SystemStatService.memGb}G`
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
        }
      }

      // Network Download Speed Component
      RowLayout {
        id: networkDownloadLayout
        spacing: Style.marginXS * scaling
        Layout.alignment: Qt.AlignVCenter
        visible: userShowNetworkStats

        NIcon {
          text: "download"
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
        }
      }

      // Network Upload Speed Component
      RowLayout {
        id: networkUploadLayout
        spacing: Style.marginXS * scaling
        Layout.alignment: Qt.AlignVCenter
        visible: userShowNetworkStats

        NIcon {
          text: "upload"
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
          font.family: Settings.data.ui.fontFixed
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignVCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
        }
      }
    }
  }
}
