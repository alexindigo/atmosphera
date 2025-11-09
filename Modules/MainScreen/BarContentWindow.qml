import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Modules.Bar


/**
 * BarContentWindow - Separate transparent PanelWindow for bar content
 *
 * This window contains only the bar widgets (content), while the background
 * is rendered in MainScreen's unified Shape system. This separation prevents
 * fullscreen redraws when bar widgets redraw.
 */
Variants {
  model: Quickshell.screens

  delegate: Loader {
    id: barWindowLoader

    required property ShellScreen modelData

    // Only create window if bar should be visible on this screen
    active: {
      if (!modelData || !modelData.name)
        return false
      var monitors = Settings.data.bar.monitors || []
      return BarService.isVisible && (monitors.length === 0 || monitors.includes(modelData.name))
    }

    sourceComponent: PanelWindow {
      id: barWindow
      screen: modelData

      color: Color.transparent // Transparent - background is in MainScreen below

      Component.onCompleted: {
        Logger.d("BarContentWindow", "Bar content window created for screen:", screen?.name)
      }

      // Wayland layer configuration
      WlrLayershell.namespace: "noctalia-bar-content-" + (screen?.name || "unknown")
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.exclusionMode: ExclusionMode.Ignore // Don't reserve space - BarExclusionZone in MainScreen handles that

      // Position and size to match bar location
      readonly property string barPosition: Settings.data.bar.position || "top"
      readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
      readonly property bool barFloating: Settings.data.bar.floating || false
      readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
      readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

      // Anchor to the bar's edge
      anchors {
        top: barPosition === "top" || barIsVertical
        bottom: barPosition === "bottom" || barIsVertical
        left: barPosition === "left" || !barIsVertical
        right: barPosition === "right" || !barIsVertical
      }
      // Set to FULL screen dimensions - margins will reduce the actual window size
      implicitWidth: (barIsVertical ? (Style.barHeight + 1) : screen.width) + barMarginH
      implicitHeight: (barIsVertical ? screen.height : Style.barHeight) + barMarginV

      // Bar content - just the widgets, no background
      Bar {
        anchors.fill: parent
        screen: modelData
      }
    }
  }
}
