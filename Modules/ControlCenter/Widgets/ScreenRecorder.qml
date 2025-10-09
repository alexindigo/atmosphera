import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NQuickSetting {
  property ShellScreen screen
  property real scaling: 1.0

  enabled: ProgramCheckerService.gpuScreenRecorderAvailable
  icon: "camera-video"
  text: "Screen Rec."
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightMedium
  active: ScreenRecorderService.isRecording
  tooltipText: ScreenRecorderService.isRecording ? "Stop recording" : "Start screen recording"
  style: Settings.data.controlCenter.quickSettingsStyle || "modern"

  onClicked: {
    ScreenRecorderService.toggleRecording()
    if (!ScreenRecorderService.isRecording) {
      var panel = PanelService.getPanel("controlCenterPanel")
      panel?.close()
    }
  }
}
