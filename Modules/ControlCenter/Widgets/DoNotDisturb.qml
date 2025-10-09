import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

  text: "Do not Disturb"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  icon: Settings.data.notifications.doNotDisturb ? "bell-off" : "bell"
  active: Settings.data.notifications.doNotDisturb
  tooltipText: Settings.data.notifications.doNotDisturb ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb"
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  onClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
}
