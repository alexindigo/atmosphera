import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: Settings.data.location.showWeekNumberInCalendar ? 350 : 330
  preferredHeight: 320

  // Main Column
  panelContent: ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM * scaling
    spacing: Style.marginXS * scaling

    // Header: Month/Year with navigation
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginM * scaling
      Layout.rightMargin: Style.marginM * scaling
      spacing: Style.marginS * scaling

      NIconButton {
        icon: "chevron-left"
        tooltipText: "Previous month"
        onClicked: {
          let newDate = new Date(grid.year, grid.month - 1, 1)
          grid.year = newDate.getFullYear()
          grid.month = newDate.getMonth()
        }
      }

      NText {
        text: grid.title
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        font.pointSize: Style.fontSizeM * scaling
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
      }

      NIconButton {
        icon: "chevron-right"
        tooltipText: "Next month"
        onClicked: {
          let newDate = new Date(grid.year, grid.month + 1, 1)
          grid.year = newDate.getFullYear()
          grid.month = newDate.getMonth()
        }
      }
    }

    // Divider between header and weekdays
    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginS * scaling
      Layout.bottomMargin: Style.marginL * scaling
    }

    // Columns label (respects locale's first day of week)
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginS * scaling // Align with grid
      Layout.rightMargin: Style.marginS * scaling
      Layout.bottomMargin: Style.marginM * scaling
      spacing: 0

      // Week header spacer or label (same width as week number column)
      Item {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * scaling : 0

        NText {
          anchors.centerIn: parent
          text: "Week"
          color: Color.mOutline
          font.pointSize: Style.fontSizeXS * scaling
          font.weight: Style.fontWeightRegular
          horizontalAlignment: Text.AlignHCenter
        }
      }

      // Day name headers - now properly aligned with calendar grid
      GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 7
        rows: 1
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
          model: 7

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: Style.baseWidgetSize * scaling

            NText {
              anchors.centerIn: parent
              text: {
                // Use the locale's first day of week setting
                let firstDay = Qt.locale().firstDayOfWeek
                let dayIndex = (firstDay + index) % 7
                return Qt.locale().dayName(dayIndex, Locale.ShortFormat)
              }
              color: Color.mSecondary
              font.pointSize: Style.fontSizeM * scaling
              font.weight: Style.fontWeightBold
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }

    // Grids: days with optional week numbers
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Style.marginS * scaling
      Layout.rightMargin: Style.marginS * scaling
      spacing: 0

      // Week numbers column (only visible when enabled)
      GridLayout {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * scaling : 0
        Layout.fillHeight: true
        columns: 1
        rows: 6
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
          model: 6 // Maximum 6 weeks in a month view

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Color.transparent

            NText {
              anchors.centerIn: parent
              color: Color.mOutline
              font.pointSize: Style.fontSizeXS * scaling
              font.weight: Style.fontWeightBold
              text: {
                // Calculate the first day shown in the calendar grid
                let firstDay = new Date(grid.year, grid.month, 1)
                let firstDayOfWeek = Qt.locale().firstDayOfWeek
                let startOffset = (firstDay.getDay() - firstDayOfWeek + 7) % 7
                let gridStartDate = new Date(grid.year, grid.month, 1 - startOffset)

                // Get the date for the start of this specific row
                let rowDate = new Date(gridStartDate)
                rowDate.setDate(gridStartDate.getDate() + (index * 7))

                // Calculate week number based on the Thursday of the visual row
                // This correctly handles rows that span two different ISO weeks.
                let thursdayOfRow = new Date(rowDate)
                let offsetToThursday = (4 - thursdayOfRow.getDay() + 7) % 7
                thursdayOfRow.setDate(thursdayOfRow.getDate() + offsetToThursday)

                // Check if this row is visible (contains days from current month)
                let rowEndDate = new Date(rowDate)
                rowEndDate.setDate(rowDate.getDate() + 6)

                if (rowDate.getMonth() === grid.month || rowEndDate.getMonth() === grid.month || (rowDate.getMonth() < grid.month && rowEndDate.getMonth() > grid.month)) {
                  return `${getISOWeekNumber(thursdayOfRow)}`
                }
                return ""
              }
            }
          }
        }
      }

      // The actual calendar grid
      MonthGrid {
        id: grid

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0
        month: Time.date.getMonth()
        year: Time.date.getFullYear()
        locale: Qt.locale()

        delegate: Rectangle {
          width: Style.baseWidgetSize * scaling
          height: Style.baseWidgetSize * scaling
          radius: Style.radiusS * scaling
          color: model.today ? Color.mPrimary : Color.transparent

          NText {
            anchors.centerIn: parent
            text: model.day
            color: model.today ? Color.mOnPrimary : Color.mOnSurface
            opacity: model.month === grid.month ? Style.opacityHeavy : Style.opacityLight
            font.pointSize: Style.fontSizeM * scaling
            font.weight: model.today ? Style.fontWeightBold : Style.fontWeightRegular
          }

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }
      }
    }
  }

  function getISOWeekNumber(date) {
    // Create a copy of the date and normalize to noon to prevent DST issues
    const targetDate = new Date(date.getTime())
    targetDate.setHours(12, 0, 0, 0)

    // Roll the date to the Thursday of the week.
    // getDay() is 0 for Sunday, we want Monday to be 1 and Sunday to be 7.
    const dayOfWeek = targetDate.getDay() || 7
    targetDate.setDate(targetDate.getDate() - dayOfWeek + 4)

    // Get the first day of that Thursday's year
    const yearStart = new Date(targetDate.getFullYear(), 0, 1)

    // Calculate the difference in days and find the week number
    const dayOfYear = ((targetDate - yearStart) / 86400000) + 1
    return Math.ceil(dayOfYear / 7)
  }
}
