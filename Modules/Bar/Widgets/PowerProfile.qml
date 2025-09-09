import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: 1.0
  readonly property bool hasPP: PowerProfileService.available

  sizeRatio: 0.8
  visible: hasPP

  function profileIcon() {
    if (!hasPP)
      return "yin-yang"
    if (PowerProfileService.profile === PowerProfile.Performance)
      return "speedometer2"
    if (PowerProfileService.profile === PowerProfile.Balanced)
      return "yin-yang"
    if (PowerProfileService.profile === PowerProfile.PowerSaver)
      return "leaf"
  }

  function profileName() {
    if (!hasPP)
      return "Unknown"
    if (PowerProfileService.profile === PowerProfile.Performance)
      return "Performance"
    if (PowerProfileService.profile === PowerProfile.Balanced)
      return "Balanced"
    if (PowerProfileService.profile === PowerProfile.PowerSaver)
      return "Power Saver"
  }

  function changeProfile() {
    if (!hasPP)
      return
    PowerProfileService.cycleProfile()
  }

  icon: root.profileIcon()
  tooltipText: root.profileName()
  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: root.changeProfile()
}
