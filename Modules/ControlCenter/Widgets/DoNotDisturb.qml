import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NButton {
  property ShellScreen screen
  property real scaling: 1.0

  outlined: true
  text: "Do not Disturb"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  icon: Settings.data.notifications.doNotDisturb  ? "bell-off" : "bell"
  onClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
}
