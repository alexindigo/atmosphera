import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Power
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: PowerProfileService.atmospheraPerformanceMode ? "rocket" : "rocket-off"
  tooltipText: I18n.tr("tooltips.atmosphera-performance-enabled")
  hot: PowerProfileService.atmospheraPerformanceMode
  onClicked: PowerProfileService.toggleAtmospheraPerformance()
}
