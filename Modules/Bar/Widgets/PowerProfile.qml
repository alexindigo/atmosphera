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

  baseSize: Style.capsuleHeight
  visible: PowerProfileService.available

  icon: PowerProfileService.getIcon()
  tooltipText: I18n.tr("tooltips.power-profile", {
                         "profile": PowerProfileService.getName()
                       })
  tooltipDirection: BarService.getTooltipDirection()
  compact: (Settings.data.bar.density === "compact") || (Settings.data.bar.density === "mini")
  colorBg: (PowerProfileService.profile === PowerProfile.Balanced) ? (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent) : Color.mPrimary
  colorFg: (PowerProfileService.profile === PowerProfile.Balanced) ? Color.mOnSurface : Color.mOnPrimary
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: PowerProfileService.cycleProfile()
}
