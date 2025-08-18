import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Row {
  id: root
  anchors.verticalCenter: parent.verticalCenter
  spacing: Style.marginSmall * scaling
  visible: (Settings.data.bar.showSystemInfo)

  Rectangle {
    // Let the Rectangle size itself based on its content (the Row)
    width: row.width + Style.marginMedium * scaling * 2

    height: Math.round(Style.barHeight * 0.75 * scaling)
    radius: Math.round(Style.radiusMedium * scaling)
    color: Color.mSurfaceVariant
    border.color: Color.mOutline
    border.width: Math.max(1, Math.round(Style.borderThin * scaling))

    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: Style.marginSmall * scaling
      anchors.rightMargin: Style.marginSmall * scaling

      Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginSmall * scaling
        Row {
          id: cpuUsageLayout
          spacing: Style.marginTiny * scaling

          NIcon {
            id: cpuUsageIcon
            text: "speed"
            anchors.verticalCenter: parent.verticalCenter
          }

          NText {
            id: cpuUsageText
            text: `${SystemStatService.cpuUsage}%`
            font.pointSize: Style.fontSizeReduced * scaling
            font.weight: Style.fontWeightMedium
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }

        // CPU Temperature Component
        Row {
          id: cpuTempLayout
          // spacing is thin here to compensate for the vertical thermometer icon
          spacing: Style.marginTiniest * scaling

          NIcon {
            text: "thermometer"
            anchors.verticalCenter: parent.verticalCenter
          }

          NText {
            text: `${SystemStatService.cpuTemp}°C`
            font.pointSize: Style.fontSizeReduced * scaling
            font.weight: Style.fontWeightMedium
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }

        // Memory Usage Component
        Row {
          id: memoryUsageLayout
          spacing: Style.marginTiny * scaling

          NIcon {
            text: "memory"
            anchors.verticalCenter: parent.verticalCenter
          }

          NText {
            text: `${SystemStatService.memoryUsageGb}G`
            font.pointSize: Style.fontSizeReduced * scaling
            font.weight: Style.fontWeightMedium
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }
        }
      }
    }
  }
}
