import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM * scaling

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowDate: widgetData.showDate !== undefined ? widgetData.showDate : widgetMetadata.showDate
  property bool valueUse12h: widgetData.use12HourClock !== undefined ? widgetData.use12HourClock : widgetMetadata.use12HourClock
  property bool valueShowSeconds: widgetData.showSeconds !== undefined ? widgetData.showSeconds : widgetMetadata.showSeconds
  property bool valueReverseDayMonth: widgetData.reverseDayMonth !== undefined ? widgetData.reverseDayMonth : widgetMetadata.reverseDayMonth

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showDate = valueShowDate
    settings.use12HourClock = valueUse12h
    settings.showSeconds = valueShowSeconds
    settings.reverseDayMonth = valueReverseDayMonth
    return settings
  }

  NCheckbox {
    label: "Show date next to time"
    checked: valueShowDate
    onToggled: checked => valueShowDate = checked
  }

  NCheckbox {
    label: "Use 12-hour clock"
    checked: valueUse12h
    onToggled: checked => valueUse12h = checked
  }

  NCheckbox {
    label: "Show seconds"
    checked: valueShowSeconds
    onToggled: checked => valueShowSeconds = checked
  }

  NCheckbox {
    label: "Reverse day and month"
    checked: valueReverseDayMonth
    onToggled: checked => valueReverseDayMonth = checked
  }
}
