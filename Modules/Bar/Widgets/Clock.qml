import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Resolve per-instance widget settings from Settings.data
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

  // Use settings or defaults from BarWidgetRegistry metadata
  readonly property bool userShowDate: (widgetSettings.showDate
                                        !== undefined) ? widgetSettings.showDate : BarWidgetRegistry.widgetMetadata["Clock"].showDate
  readonly property bool userUse12h: (widgetSettings.use12HourClock !== undefined) ? widgetSettings.use12HourClock : BarWidgetRegistry.widgetMetadata["Clock"].use12HourClock
  readonly property bool userShowSeconds: (widgetSettings.showSeconds !== undefined) ? widgetSettings.showSeconds : BarWidgetRegistry.widgetMetadata["Clock"].showSeconds

  implicitWidth: clock.width + Style.marginM * 2 * scaling
  implicitHeight: Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Color.mSurfaceVariant

  // Clock Icon with attached calendar
  NClock {
    id: clock
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    // Per-instance overrides to Time formatting
    showDate: userShowDate
    use12h: userUse12h
    showSeconds: userShowSeconds

    NTooltip {
      id: tooltip
      text: `${Time.dateString}.`
      target: clock
      positionAbove: Settings.data.bar.position === "bottom"
    }

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
      PanelService.getPanel("calendarPanel")?.toggle(screen, this)
    }
  }
}
