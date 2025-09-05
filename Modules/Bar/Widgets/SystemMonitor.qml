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

        NIcon {
          text: "memory"
          Layout.alignment: Qt.AlignVCenter
        }

        NText {
          text: `${SystemStatService.memoryUsageGb}G`
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
        visible: Settings.data.bar.showNetworkStats

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
        visible: Settings.data.bar.showNetworkStats

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
