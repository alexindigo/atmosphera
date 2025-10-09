import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NButton {
  property ShellScreen screen
  property real scaling: 1.0

  outlined: true
  text: IdleInhibitorService.isInhibited ? "Keep-awake" : "Keep-awake"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  icon: IdleInhibitorService.isInhibited ? "keep-awake-on" : "keep-awake-off"
  onClicked: IdleInhibitorService.manualToggle()
}
