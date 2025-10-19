import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

NPanel {
  sourceComponent: Component {
    // PanelWindow has its own screen property inherited of QsWindow
    NPanelWindow {
      loggerPrefix: "NPanelOverlay"
      WlrLayershell.layer: WlrLayer.Overlay
    }
  }
}
