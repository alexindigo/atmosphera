import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar
import qs.Services.UI

/**
* BarContentWindow - Separate transparent PanelWindow for bar content
*
* This window contains only the bar widgets (content), while the background
* is rendered in MainScreen's unified Shape system. This separation prevents
* fullscreen redraws when bar widgets redraw.
*
* This component should be instantiated once per screen by AllScreens.qml
*/
PanelWindow {
  id: barWindow

  // Note: screen property is inherited from PanelWindow and should be set by parent
  color: "transparent" // Transparent - background is in MainScreen below

  Component.onCompleted: {
    Logger.d("BarContentWindow", "Bar content window created for screen:", barWindow.screen?.name);
  }

  // Wayland layer configuration
  WlrLayershell.namespace: "noctalia-bar-content-" + (barWindow.screen?.name || "unknown")
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone in MainScreen handles that

  // Position and size to match bar location (per-screen)
  readonly property string barPosition: Settings.getBarPositionForScreen(barWindow.screen?.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool isFramed: Settings.data.bar.barType === "framed"
  readonly property real frameThickness: Settings.data.bar.frameThickness ?? 12
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property real barMarginH: Math.ceil(barFloating ? Settings.data.bar.marginHorizontal : 0)
  readonly property real barMarginV: Math.ceil(barFloating ? Settings.data.bar.marginVertical : 0)
  readonly property real barHeight: Style.getBarHeightForScreen(barWindow.screen?.name)

  // Anchor to the bar's edge
  anchors {
    top: barPosition === "top" || barIsVertical
    bottom: barPosition === "bottom" || barIsVertical
    left: barPosition === "left" || !barIsVertical
    right: barPosition === "right" || !barIsVertical
  }

  // Handle floating margins and framed mode offsets
  margins {
    top: (barPosition === "top") ? barMarginV : (isFramed ? frameThickness : barMarginV)
    bottom: (barPosition === "bottom") ? barMarginV : (isFramed ? frameThickness : barMarginV)
    left: (barPosition === "left") ? barMarginH : (isFramed ? frameThickness : barMarginH)
    right: (barPosition === "right") ? barMarginH : (isFramed ? frameThickness : barMarginH)
  }

  // Set a tight window size
  implicitWidth: barIsVertical ? barHeight : barWindow.screen.width
  implicitHeight: barIsVertical ? barWindow.screen.height : barHeight

  // Bar content - just the widgets, no background
  Bar {
    anchors.fill: parent
    screen: barWindow.screen
  }
}
