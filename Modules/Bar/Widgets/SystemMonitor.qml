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

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
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

  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage
                                        !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage
                                           !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent
                                               !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats
                                            !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats

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
        visible: showCpuUsage

        NIcon {
          id: cpuUsageIcon
          text: Bootstrap.icons["speed"]
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
        visible: showCpuTemp

        NIcon {
          text: Bootstrap.icons["thermometer"]
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
        visible: showMemoryUsage

        NIcon {
          text: Bootstrap.icons["memory"]
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: showMemoryAsPercent ? `${SystemStatService.memPercent}%` : `${SystemStatService.memGb}G`
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
        visible: showNetworkStats

        NIcon {
          text: Bootstrap.icons["download"]
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
        visible: showNetworkStats

        NIcon {
          text: Bootstrap.icons["upload"]
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
