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

  readonly property var now: Time.date

  preferredWidth: (Settings.data.location.showWeekNumberInCalendar ? 400 : 380) * Style.uiScaleRatio
  preferredHeight: 520 * Style.uiScaleRatio
  panelKeyboardFocus: true

  panelContent: ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    property bool isCurrentMonth: checkIsCurrentMonth()
    readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)

    function checkIsCurrentMonth() {
      return (Time.date.getMonth() === grid.month) && (Time.date.getFullYear() === grid.year)
    }

    Shortcut {
      sequence: "Escape"
      onActivated: {
        if (timerActive) {
          cancelTimer()
        } else {
          cancelTimer()
          root.close()
        }
      }
      context: Qt.WidgetShortcut
      enabled: root.opened
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
      Layout.preferredHeight: blueColumn.implicitHeight + Style.marginM * 2
      radius: Style.radiusL
      color: Color.mPrimary

      ColumnLayout {
        id: blueColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.marginM
        anchors.leftMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        anchors.rightMargin: clockItem.width + (Style.marginM * 2)
        spacing: 0

        // Combined layout for weather icon, date, and weather text
        RowLayout {
          Layout.fillWidth: true
          height: 60 * Style.uiScaleRatio
          clip: true
          spacing: Style.marginS

          // Weather icon and temperature
          ColumnLayout {
            visible: Settings.data.location.weatherEnabled && weatherReady
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.marginXXS

            NIcon {
              Layout.alignment: Qt.AlignHCenter
              icon: Settings.data.location.weatherEnabled && weatherReady ? LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode) : ""
              pointSize: Style.fontSizeXXL
              color: Color.mOnPrimary
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: {
                if (!Settings.data.location.weatherEnabled)
                  return ""
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
              pointSize: Style.fontSizeM
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
            pointSize: Style.fontSizeXXXL * 1.5
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
            Layout.preferredWidth: 170 * Style.uiScaleRatio
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            Layout.bottomMargin: Style.marginXXS
            Layout.topMargin: -Style.marginXXS
            spacing: -Style.marginXS

            RowLayout {
              spacing: 0

              NText {
                text: Qt.locale().monthName(grid.month, Locale.LongFormat).toUpperCase()
                pointSize: Style.fontSizeXL * 1.1
                font.weight: Style.fontWeightBold
                color: Color.mOnPrimary
                Layout.alignment: Qt.AlignBaseline
                elide: Text.ElideRight
              }

              NText {
                text: ` ${grid.year}`
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightBold
                color: Qt.alpha(Color.mOnPrimary, 0.7)
                Layout.alignment: Qt.AlignBaseline
              }
            }

            RowLayout {
              spacing: 0

              NText {
                text: {
                  if (!Settings.data.location.weatherEnabled)
                    return ""
                  if (!weatherReady)
                    return I18n.tr("calendar.weather.loading")
                  const chunks = Settings.data.location.name.split(",")
                  return chunks[0]
                }
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightMedium
                color: Color.mOnPrimary
                Layout.maximumWidth: 150
                elide: Text.ElideRight
              }

              NText {
                text: weatherReady ? ` (${LocationService.data.weather.timezone_abbreviation})` : ""
                pointSize: Style.fontSizeXS
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
        anchors.rightMargin: Style.marginM
        anchors.verticalCenter: parent.verticalCenter
        height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
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
            var radius = Math.min(width, height) / 2 - 3
            ctx.reset()

            // Background circle
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
            ctx.lineWidth = 2.5
            ctx.strokeStyle = Qt.alpha(Color.mOnPrimary, 0.15)
            ctx.stroke()

            // Progress arc
            ctx.beginPath()
            ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
            ctx.lineWidth = 2.5
            ctx.strokeStyle = Color.mOnPrimary
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }

        // Digital clock
        ColumnLayout {
          anchors.centerIn: parent
          spacing: -Style.marginXXS

          NText {
            text: {
              var t = Settings.data.location.use12hourFormat ? Qt.locale().toString(now, "hh AP") : Qt.locale().toString(now, "HH")
              return t.split(" ")[0]
            }

            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary
            family: Settings.data.ui.fontFixed
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: Qt.formatTime(now, "mm")
            pointSize: Style.fontSizeXXS
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
      spacing: Style.marginL
      Repeater {
        model: weatherReady ? Math.min(6, LocationService.data.weather.daily.time.length) : 0
        delegate: ColumnLayout {
          Layout.preferredWidth: 0
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginS
          NText {
            text: {
              var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"))
              return Qt.locale().toString(weatherDate, "ddd")
            }
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
            font.weight: Style.fontWeightMedium
            Layout.alignment: Qt.AlignHCenter
          }
          NIcon {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
            pointSize: Style.fontSizeXXL * 1.5
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
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            font.weight: Style.fontWeightMedium
          }
        }
      }
    }
    RowLayout {
      visible: Settings.data.location.weatherEnabled && !weatherReady
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      NBusyIndicator {}
    }
    Item {}
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
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
        }
      }
      NIconButton {
        icon: "calendar"
        onClicked: {
          grid.month = Time.date.getMonth()
          grid.year = Time.date.getFullYear()
          content.isCurrentMonth = true
        }
      }
      NIconButton {
        icon: "chevron-right"
        onClicked: {
          let newDate = new Date(grid.year, grid.month + 1, 1)
          grid.year = newDate.getFullYear()
          grid.month = newDate.getMonth()
          content.isCurrentMonth = content.checkIsCurrentMonth()
        }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      spacing: 0
      Item {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 : 0
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
            Layout.preferredHeight: Style.baseWidgetSize * 0.6
            NText {
              anchors.centerIn: parent
              text: {
                let dayIndex = (content.firstDayOfWeek + index) % 7
                const dayNames = ["S", "M", "T", "W", "T", "F", "S"]
                return dayNames[dayIndex]
              }
              color: Color.mPrimary
              pointSize: Style.fontSizeS
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
      ColumnLayout {
        visible: Settings.data.location.showWeekNumberInCalendar
        Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.7 : 0
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
              pointSize: Style.fontSizeXXS
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
        spacing: Style.marginXXS
        month: Time.date.getMonth()
        year: Time.date.getFullYear()
        locale: Qt.locale()
        delegate: Item {
          Rectangle {
            width: Style.baseWidgetSize * 0.9
            height: Style.baseWidgetSize * 0.9
            anchors.centerIn: parent
            radius: Style.radiusM
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
              pointSize: Style.fontSizeM
              font.weight: model.today ? Style.fontWeightBold : Style.fontWeightMedium
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
