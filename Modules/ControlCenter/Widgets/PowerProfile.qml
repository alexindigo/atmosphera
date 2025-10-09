import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets

// Performance
NButton {
  property ShellScreen screen
  property real scaling: 1.0
  readonly property bool hasPP: PowerProfileService.available

  enabled: hasPP
  outlined: true
  text: PowerProfileService.getName()
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  icon: PowerProfileService.getIcon()
  onClicked: {
    PowerProfileService.cycleProfile()
  }
}
