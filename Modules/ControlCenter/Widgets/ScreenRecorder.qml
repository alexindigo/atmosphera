import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NButton {

  property ShellScreen screen
  property real scaling: 1.0

  enabled: ProgramCheckerService.gpuScreenRecorderAvailable
  outlined: true
  icon: "camera-video"
  text: "Screen Rec."
  fontSize: Style.fontSizeS * scaling
  fontWeight: Style.fontWeightRegular
  onClicked: {
    ScreenRecorderService.toggleRecording()
    if (!ScreenRecorderService.isRecording) {
      var panel = PanelService.getPanel("controlCenterPanel")
      panel?.close()
    }
  }
}
