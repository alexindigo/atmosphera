import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

  text: "Keep-awake"
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  icon: IdleInhibitorService.isInhibited ? "keep-awake-on" : "keep-awake-off"
  active: IdleInhibitorService.isInhibited
  tooltipText: IdleInhibitorService.isInhibited ? "Disable keep-awake" : "Enable keep-awake"
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  onClicked: IdleInhibitorService.manualToggle()
}
