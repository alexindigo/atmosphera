import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen

  enabled: ProgramCheckerService.gpuScreenRecorderAvailable
  icon: "camera-video"
  hot: ScreenRecorderService.isRecording
  tooltipText: I18n.tr("quickSettings.screenRecorder.tooltip.action")

  // Force hover state when recording to get hover colors
  property bool originalHovered: hovered
  hovered: ScreenRecorderService.isRecording || originalHovered

  onClicked: {
    ScreenRecorderService.toggleRecording()
    if (!ScreenRecorderService.isRecording) {
      var panel = PanelService.getPanel("controlCenterPanel")
      panel?.close()
    }
  }
}
