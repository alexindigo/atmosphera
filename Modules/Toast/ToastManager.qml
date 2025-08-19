import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

// ToastManager creates toast overlays on each screen
Variants {
  model: Quickshell.screens

  delegate: PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property real scaling: ScalingService.scale(screen)
    screen: modelData

    // Position at top, centered horizontally
    anchors {
      top: true
      left: true
      right: true
    }
    
    // Small height when hidden, appropriate height when visible
    implicitHeight: toast.visible ? toast.height + Style.barHeight * scaling + Style.marginS * scaling : 1

    // Transparent background
    color: Color.transparent
    
    // High layer to appear above other panels  
    //WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: PanelWindow.ExclusionMode.Ignore

    NToast {
      id: toast
      scaling: root.scaling
      
      // Position just below where the bar would be
      targetY: Style.barHeight * scaling + Style.marginS * scaling
      
      Component.onCompleted: {
        // Register this toast with the service
        ToastService.currentToast = toast
        
        // Connect dismissal signal
        toast.dismissed.connect(ToastService.onToastDismissed)
      }
    }
  }
}