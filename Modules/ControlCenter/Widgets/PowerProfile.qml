import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets

// Performance
NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0
  readonly property bool hasPP: PowerProfileService.available

  enabled: hasPP
  text: PowerProfileService.getName()
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  icon: PowerProfileService.getIcon()
  active: hasPP
  tooltipText: hasPP ? "Current: " + PowerProfileService.getName() : "Power profiles not available"
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  onClicked: {
    PowerProfileService.cycleProfile()
  }
}
