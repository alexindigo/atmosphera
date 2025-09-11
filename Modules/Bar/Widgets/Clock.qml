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

  // Resolve settings: try user settings or defaults from BarWidgetRegistry
  readonly property bool use12h: widgetSettings.use12HourClock !== undefined ? widgetSettings.use12HourClock : widgetMetadata.use12HourClock
  readonly property bool reverseDayMonth: widgetSettings.reverseDayMonth
                                          !== undefined ? widgetSettings.reverseDayMonth : widgetMetadata.reverseDayMonth
  readonly property string displayFormat: widgetSettings.displayFormat
                                          !== undefined ? widgetSettings.displayFormat : widgetMetadata.displayFormat

  implicitWidth: Math.round(layout.implicitWidth + Style.marginM * 2 * scaling)
  implicitHeight: Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusS * scaling)
  color: Color.mSurfaceVariant

  Item {
    id: clockContainer
    anchors.fill: parent
    anchors.margins: Style.marginXS * scaling

    ColumnLayout {
      id: layout
      anchors.centerIn: parent
      spacing: -3 * scaling

      // First line
      NText {
        readonly property bool showSeconds: (displayFormat === "time-seconds")
        readonly property bool inlineDate: (displayFormat === "time-date")

        text: {
          const now = Time.date
          let timeStr = ""

          if (use12h) {
            // 12-hour format with proper padding and consistent spacing
            const hours = now.getHours()
            const displayHours = hours === 0 ? 12 : (hours > 12 ? hours - 12 : hours)
            const paddedHours = displayHours.toString().padStart(2, '0')
            const minutes = now.getMinutes().toString().padStart(2, '0')
            const ampm = hours < 12 ? 'AM' : 'PM'

            if (showSeconds) {
              const seconds = now.getSeconds().toString().padStart(2, '0')
              timeStr = `${paddedHours}:${minutes}:${seconds} ${ampm}`
            } else {
              timeStr = `${paddedHours}:${minutes} ${ampm}`
            }
          } else {
            // 24-hour format with padding
            const hours = now.getHours().toString().padStart(2, '0')
            const minutes = now.getMinutes().toString().padStart(2, '0')

            if (showSeconds) {
              const seconds = now.getSeconds().toString().padStart(2, '0')
              timeStr = `${hours}:${minutes}:${seconds}`
            } else {
              timeStr = `${hours}:${minutes}`
            }
          }

          // Add inline date if needed
          if (inlineDate) {
            let dayName = now.toLocaleDateString(Qt.locale(), "ddd")
            dayName = dayName.charAt(0).toUpperCase() + dayName.slice(1)
            const day = now.getDate().toString().padStart(2, '0')
            let month = now.toLocaleDateString(Qt.locale(), "MMM")
            timeStr += " - " + (reverseDayMonth ? `${dayName}, ${month} ${day}` : `${dayName}, ${day} ${month}`)
          }

          return timeStr
        }

        //font.family: Settings.data.ui.fontFixed
        font.pointSize: Style.fontSizeXS * scaling
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
      }

      // Second line
      NText {
        visible: (displayFormat === "time-date-short")
        text: {
          const now = Time.date
          const day = now.getDate().toString().padStart(2, '0')
          const month = (now.getMonth() + 1).toString().padStart(2, '0')
          return reverseDayMonth ? `${month}/${day}` : `${day}/${month}`
        }

        // Enable fixed-width font for consistent spacing
        //font.family: Settings.data.ui.fontFixed
        font.pointSize: Style.fontSizeXXS * scaling
        font.weight: Style.fontWeightRegular
        color: Color.mPrimary
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
      }
    }
  }

  NTooltip {
    id: tooltip
    text: `${Time.formatDate(reverseDayMonth)}.`
    target: clockContainer
    positionAbove: Settings.data.bar.position === "bottom"
  }

  MouseArea {
    id: clockMouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: {
      if (!PanelService.getPanel("calendarPanel")?.active) {
        tooltip.show()
      }
    }
    onExited: {
      tooltip.hide()
    }
    onClicked: {
      tooltip.hide()
      PanelService.getPanel("calendarPanel")?.toggle(this)
    }
  }
}
