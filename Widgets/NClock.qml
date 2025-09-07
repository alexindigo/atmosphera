import QtQuick
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  signal entered
  signal exited
  signal clicked

  // Per-instance overrides (default to global settings if not provided by parent)
  // Parent widgets like Bar `Clock.qml` can bind these
  property bool showDate: Settings.data.location.showDateWithClock
  property bool use12h: Settings.data.location.use12HourClock
  property bool showSeconds: false

  width: textItem.paintedWidth
  height: textItem.paintedHeight
  color: Color.transparent

  NText {
    id: textItem
    text: {
      const now = Time.date
      const timeFormat = use12h ? (showSeconds ? "h:mm:ss AP" : "h:mm AP") : (showSeconds ? "HH:mm:ss" : "HH:mm")
      const timeString = Qt.formatDateTime(now, timeFormat)

      if (showDate) {
        let dayName = now.toLocaleDateString(Qt.locale(), "ddd")
        dayName = dayName.charAt(0).toUpperCase() + dayName.slice(1)
        let day = now.getDate()
        let month = now.toLocaleDateString(Qt.locale(), "MMM")
        return timeString + " - " + (Settings.data.location.reverseDayMonth ? `${dayName}, ${month} ${day}` : `${dayName}, ${day} ${month}`)
      }
      return timeString
    }
    anchors.centerIn: parent
    font.pointSize: Style.fontSizeS * scaling
    font.weight: Style.fontWeightBold
  }

  MouseArea {
    id: clockMouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: root.entered()
    onExited: root.exited()
    onClicked: root.clicked()
  }
}
