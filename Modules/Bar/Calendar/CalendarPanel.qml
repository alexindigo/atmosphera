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

  property ShellScreen screen
  readonly property var now: Time.date

  preferredWidth: Settings.data.location.showWeekNumberInCalendar ? 400 : 380
  preferredHeight: 520

  panelContent: ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginL * scaling
    spacing: Style.marginM * scaling

    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    property bool isCurrentMonth: checkIsCurrentMonth()
    readonly property bool weatherReady: (LocationService.data.weather !== null)

    function checkIsCurrentMonth() {
      return (Time.date.getMonth() === grid.month) && (Time.date.getFullYear() === grid.year)
    }

    Connections {
      target: Time
      function onDateChanged() {
        isCurrentMonth = checkIsCurrentMonth()
      }
    }

    // Combined blue banner with date/time and weather summary
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: blueColumn.implicitHeight + Style.marginM * scaling * 2
      radius: Style.radiusL * scaling
      color: Color.mPrimary

      ColumnLayout {
        id: blueColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.marginM * scaling
        anchors.leftMargin: Style.marginM * scaling
        anchors.bottomMargin: Style.marginM * scaling
        anchors.rightMargin: clockItem.width + (Style.marginM * scaling * 2)
        spacing: 0

        // Combined layout for weather icon, date, and weather text
        RowLayout {
          Layout.fillWidth: true
          height: 60 * scaling
          clip: true
          spacing: Style.marginS * scaling

          // Weather icon and temperature
          ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.marginXXS * scaling

            NIcon {
              Layout.alignment: Qt.AlignHCenter
              icon: weatherReady ? LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode) : "cloud"
              pointSize: Style.fontSizeXXL * scaling
              color: Color.mOnPrimary
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: {
                if (!weatherReady)
                  return ""
                var temp = LocationService.data.weather.current_weather.temperature
                var suffix = "C"
                if (Settings.data.location.useFahrenheit) {
                  temp = LocationService.celsiusToFahrenheit(temp)
                  suffix = "F"
                }
                temp = Math.round(temp)
                return `${temp}°${suffix}`
              }
              pointSize: Style.fontSizeM * scaling
              font.weight: Style.fontWeightBold
              color: Color.mOnPrimary
            }
          }

          // Today day number - with simple, stable animation
          NText {
            opacity: content.isCurrentMonth ? 1.0 : 0.0
            Layout.preferredWidth: content.isCurrentMonth ? implicitWidth : 0
            elide: Text.ElideNone
            clip: true

            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            text: Time.date.getDate()
            pointSize: Style.fontSizeXXXL * 1.5 * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
            Behavior on Layout.preferredWidth {
              NumberAnimation {
                duration: Style.animationFast
                easing.type: Easing.InOutQuad
              }
            }
          }

          // Month, year, location
          ColumnLayout {
            Layout.preferredWidth: 170 * scaling
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            Layout.bottomMargin: Style.marginXXS * scaling
            Layout.topMargin: -Style.marginXXS * scaling
            spacing: -Style.marginXS * scaling

            RowLayout {
              spacing: 0

              NText {
                text: Qt.locale().monthName(grid.month, Locale.LongFormat).toUpperCase()
                pointSize: Style.fontSizeXL * 1.1 * scaling
                font.weight: Style.fontWeightBold
                color: Color.mOnPrimary
                Layout.alignment: Qt.AlignBaseline
                elide: Text.ElideRight
              }

              NText {
                text: ` ${grid.year}`
                pointSize: Style.fontSizeM * scaling
                font.weight: Style.fontWeightBold
                color: Qt.alpha(Color.mOnPrimary, 0.7)
                Layout.alignment: Qt.AlignBaseline
              }
            }

            RowLayout {
              spacing: 0

              NText {
                text: {
                  if (!weatherReady)
                    return I18n.tr("calendar.weather.loading")
                  const chunks = Settings.data.location.name.split(",")
                  return chunks[0]
                }
                pointSize: Style.fontSizeM * scaling
                font.weight: Style.fontWeightMedium
                color: Color.mOnPrimary
                Layout.maximumWidth: 150 * scaling
                elide: Text.ElideRight
              }

              NText {
                text: weatherReady ? ` (${LocationService.data.weather.timezone_abbreviation})` : ""
                pointSize: Style.fontSizeXS * scaling
                font.weight: Style.fontWeightMedium
                color: Qt.alpha(Color.mOnPrimary, 0.7)
              }
            }
          }

          // Spacer to push content left
          Item {
            Layout.fillWidth: true
          }
        }
      }

      // Digital clock with circular progress
      Item {
        id: clockItem
        Layout.alignment: Qt.AlignVCenter
        anchors.right: parent.right
        anchors.rightMargin: Style.marginM * scaling
        anchors.verticalCenter: parent.verticalCenter
        height: Math.round((Style.fontSizeXXXL * 1.9 * scaling) / 2) * 2
        width: clockItem.height

        // Seconds circular progress
        Canvas {
          id: secondsProgress
          anchors.fill: parent
          property real progress: now.getSeconds() / 60
          onProgressChanged: requestPaint()
          Connections {
            target: Time
            function onDateChanged() {
              const total = now.getSeconds() * 1000 + now.getMilliseconds()
              secondsProgress.progress = total / 60000
            }
          }
          onPaint: {
            var ctx = getContext("2d")
            var centerX = width / 2
            var centerY = height / 2
            var radius = Math.min(width, height) / 2 - 3 * scaling
            ctx.reset()

            // Background circle
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
            ctx.lineWidth = 2.5 * scaling
            ctx.strokeStyle = Qt.alpha(Color.mOnPrimary, 0.15)
            ctx.stroke()

            // Progress arc
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
            ctx.lineWidth = 2.5 * scaling
            ctx.strokeStyle = Color.mOnPrimary
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }

        // Digital clock
        ColumnLayout {
          anchors.centerIn: parent
          spacing: -Style.marginXXS * scaling

          NText {
            text: {
              var t = Settings.data.location.use12hourFormat ? Qt.locale().toString(now, "hh AP") : Qt.locale().toString(now, "HH")
              return t.split(" ")[0]
            }

            pointSize: Style.fontSizeXS * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary
            family: Settings.data.ui.fontFixed
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: Qt.formatTime(now, "mm")
            pointSize: Style.fontSizeXXS * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary
            family: Settings.data.ui.fontFixed
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }
    }

    // ... (rest of the file is unchanged) ...
    RowLayout {
      visible: weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginL * scaling
      Repeater {
        model: weatherReady ? Math.min(6, LocationService.data.weather.daily.time.length) : 0
        delegate: ColumnLayout {
          Layout.preferredWidth: 0
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginS * scaling
          NText {
            text: {
              var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"))
              return Qt.locale().toString(weatherDate, "ddd")
            }
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM * scaling
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignHCenter
          }
          NIcon {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
            pointSize: Style.fontSizeXXL * 1.5 * scaling
            color: Color.mPrimary
          }
          NText {
            Layout.alignment: Qt.AlignHCenter
            text: {
              var max = LocationService.data.weather.daily.temperature_2m_max[index]
              var min = LocationService.data.weather.daily.temperature_2m_min[index]
              if (Settings.data.location.useFahrenheit) {
                max = LocationService.celsiusToFahrenheit(max)
                min = LocationService.celsiusToFahrenheit(min)
              }
              max = Math.round(max)
              min = Math.round(min)
              return `${max}°/${min}°`
            }
            pointSize: Style.fontSizeXS * scaling
            color: Color.mOnSurfaceVariant
            font.weight: Style.fontWeightMedium
          }
        }
      }
    }
    RowLayout {
      visible: !weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      NBusyIndicator {}
    }
    Item {}
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS * scaling
      NDivider {
        Layout.fillWidth: true
      }
      NIconButton {
        icon: "chevron-left"
        onClicked: {
          let newDate = new Date(grid.year, grid.month - 1, 1)
          grid.year = newDate.getFullYear()
          grid.month = newDate.getMonth()
          content.isCurrentMonth = content.checkIsCurrentMonth()
          const now = new Date()
          const monthStart = new Date(grid.year, grid.month, 1)
          const monthEnd = new Date(grid.year, grid.month + 1, 0)

          const daysBehind = Math.max(0, Math.ceil((now - monthStart) / (24 * 60 * 60 * 1000)))
          const daysAhead = Math.max(0, Math.ceil((monthEnd - now) / (24 * 60 * 60 * 1000)))

          CalendarService.loadEvents(daysAhead + 30, daysBehind + 30)
        }
      }
      NIconButton {
        icon: "calendar"
        onClicked: {
          grid.month = Time.date.getMonth()
          grid.year = Time.date.getFullYear()
          content.isCurrentMonth = true
          CalendarService.loadEvents()
        }
      }
      NIconButton {
        icon: "chevron-right"
        onClicked: {
          let newDate = new Date(grid.year, grid.month + 1, 1)
          grid.year = newDate.getFullYear()
          grid.month = newDate.getMonth()
          content.isCurrentMonth = content.checkIsCurrentMonth()
          const now = new Date()
          const monthStart = new Date(grid.year, grid.month, 1)
          const monthEnd = new Date(grid.year, grid.month + 1, 0)

          const daysBehind = Math.max(0, Math.ceil((now - monthStart) / (24 * 60 * 60 * 1000)))
          const daysAhead = Math.max(0, Math.ceil((monthEnd - now) / (24 * 60 * 60 * 1000)))

          CalendarService.loadEvents(daysAhead + 30, daysBehind + 30)
        }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      spacing: 0
      Item {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 * scaling : 0
      }
      GridLayout {
        Layout.fillWidth: true
        columns: 7
        rows: 1
        columnSpacing: 0
        rowSpacing: 0
        Repeater {
          model: 7
          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.baseWidgetSize * 0.6 * scaling
            NText {
              anchors.centerIn: parent
              text: {
                let dayIndex = (content.firstDayOfWeek + index) % 7
                const dayNames = ["S", "M", "T", "W", "T", "F", "S"]
                return dayNames[dayIndex]
              }
              color: Color.mPrimary
              pointSize: Style.fontSizeS * scaling
              font.weight: Style.fontWeightBold
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      // Helper function to check if a date has events
      function hasEventsOnDate(year, month, day) {
        if (!CalendarService.available || CalendarService.events.length === 0)
          return false

        const targetDate = new Date(year, month, day)
        const targetStart = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime() / 1000
        const targetEnd = targetStart + 86400 // +24 hours

        return CalendarService.events.some(event => {
                                             // Check if event starts or overlaps with this day
                                             return (event.start >= targetStart && event.start < targetEnd) || (event.end > targetStart && event.end <= targetEnd) || (event.start < targetStart && event.end > targetEnd)
                                           })
      }

      // Helper function to get events for a specific date
      function getEventsForDate(year, month, day) {
        if (!CalendarService.available || CalendarService.events.length === 0)
          return []

        const targetDate = new Date(year, month, day)
        const targetStart = Math.floor(new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate()).getTime() / 1000)
        const targetEnd = targetStart + 86400 // +24 hours

        return CalendarService.events.filter(event => {
                                               return (event.start >= targetStart && event.start < targetEnd) || (event.end > targetStart && event.end <= targetEnd) || (event.start < targetStart && event.end > targetEnd)
                                             })
      }

      // Helper function to check if an event is all-day
      function isAllDayEvent(event) {
        const duration = event.end - event.start
        const startDate = new Date(event.start * 1000)
        const isAtMidnight = startDate.getHours() === 0 && startDate.getMinutes() === 0
        return duration === 86400 && isAtMidnight
      }

      // Helper function to check if an event is multi-day
      function isMultiDayEvent(event) {
        if (isAllDayEvent(event)) {
          return false
        }

        const startDate = new Date(event.start * 1000)
        const endDate = new Date(event.end * 1000)

        const startDateOnly = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate())
        const endDateOnly = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate())

        return startDateOnly.getTime() !== endDateOnly.getTime()
      }

      // Helper function to get color for a specific event
      function getEventColor(event, isToday) {
        if (isMultiDayEvent(event)) {
          return isToday ? Color.mOnSecondary : "#c4a7e7"
        } else if (isAllDayEvent(event)) {
          return isToday ? Color.mOnSecondary : Color.mSecondary
        } else {
          return isToday ? Color.mOnSecondary : Color.mPrimary
        }
      }

      // Column of week numbers
      ColumnLayout {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 * scaling : 0
        Layout.fillHeight: true
        spacing: 0
        Repeater {
          model: 6
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            NText {
              anchors.centerIn: parent
              color: Color.mOutline
              pointSize: Style.fontSizeXXS * scaling
              font.weight: Style.fontWeightMedium
              text: {
                let firstOfMonth = new Date(grid.year, grid.month, 1)
                let firstDayOfWeek = content.firstDayOfWeek
                let firstOfMonthDayOfWeek = firstOfMonth.getDay()
                let daysBeforeFirst = (firstOfMonthDayOfWeek - firstDayOfWeek + 7) % 7
                if (daysBeforeFirst === 0) {
                  daysBeforeFirst = 7
                }
                let gridStartDate = new Date(grid.year, grid.month, 1 - daysBeforeFirst)
                let rowStartDate = new Date(gridStartDate)
                rowStartDate.setDate(gridStartDate.getDate() + (index * 7))
                let thursday = new Date(rowStartDate)
                if (firstDayOfWeek === 0) {
                  thursday.setDate(rowStartDate.getDate() + 4)
                } else if (firstDayOfWeek === 1) {
                  thursday.setDate(rowStartDate.getDate() + 3)
                } else {
                  let daysToThursday = (4 - firstDayOfWeek + 7) % 7
                  thursday.setDate(rowStartDate.getDate() + daysToThursday)
                }
                return `${getISOWeekNumber(thursday)}`
              }
            }
          }
        }
      }
      MonthGrid {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginXXS * scaling
        month: Time.date.getMonth()
        year: Time.date.getFullYear()
        locale: Qt.locale()
        delegate: Item {
          Rectangle {
            width: Style.baseWidgetSize * 0.9 * scaling
            height: Style.baseWidgetSize * 0.9 * scaling
            anchors.centerIn: parent
            radius: Style.radiusM * scaling
            color: model.today ? Color.mSecondary : Color.transparent
            NText {
              anchors.centerIn: parent
              text: model.day
              color: {
                if (model.today)
                  return Color.mOnSecondary
                if (model.month === grid.month)
                  return Color.mOnSurface
                return Color.mOnSurfaceVariant
              }
              opacity: model.month === grid.month ? 1.0 : 0.4
              pointSize: Style.fontSizeM * scaling
              font.weight: model.today ? Style.fontWeightBold : Style.fontWeightMedium
            }

            // Event indicator dots
            Row {
              visible: parent.parent.parent.parent.parent.hasEventsOnDate(model.year, model.month, model.day)
              spacing: 2 * scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.marginXS * scaling

              readonly property int currentYear: model.year
              readonly property int currentMonth: model.month
              readonly property int currentDay: model.day
              readonly property bool isToday: model.today

              Repeater {
                model: parent.parent.parent.parent.parent.parent.getEventsForDate(parent.currentYear, parent.currentMonth, parent.currentDay)

                Rectangle {
                  width: 4 * scaling
                  height: 4 * scaling
                  radius: 2 * scaling
                  color: parent.parent.parent.parent.parent.parent.getEventColor(modelData, model.today)
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true

              onEntered: {
                const events = parent.parent.parent.parent.parent.getEventsForDate(model.year, model.month, model.day)
                if (events.length > 0) {
                  const summaries = events.map(e => e.summary).join('\n')
                  TooltipService.show(Screen, parent, summaries)
                  TooltipService.updateText(summaries)
                }
              }

              onClicked: {
                const dateWithSlashes = `${model.month.toString().padStart(2, '0')}/${model.day.toString().padStart(2, '0')}/${model.year.toString().substring(2)}`
                Quickshell.execDetached(["gnome-calendar", "--date", dateWithSlashes])
              }

              onExited: {
                TooltipService.hide()
              }
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
      const target = new Date(date.getTime())
      target.setHours(0, 0, 0, 0)
      const dayOfWeek = target.getDay() || 7
      target.setDate(target.getDate() + 4 - dayOfWeek)
      const yearStart = new Date(target.getFullYear(), 0, 1)
      const weekNumber = Math.ceil(((target - yearStart) / 86400000 + 1) / 7)
      return weekNumber
    }
  }
}
