import QtQuick
import Quickshell
import qs.Commons

// Niri Windows Map — panel content loaded by PluginPanelSlot (a SmartPanel).
// The slot passes through these behavior opt-outs, making the panel a
// persistent, click-through, non-dimming, non-exclusive overlay anchored
// bottom-right, with the bottom-right corner flattened into the screen edge.
Item {
  id: root

  // Injected by PluginPanelSlot
  property var pluginApi: null
  property var screen: null

  anchors.fill: parent

  // SmartPanel anchors (passed through by the slot)
  readonly property bool panelAnchorRight: true
  readonly property bool panelAnchorBottom: true

  // SmartPanel behavior opt-outs (passed through by the slot)
  readonly property bool dimEnabled: false
  readonly property bool closeOnClickOutside: false
  readonly property bool exclusiveKeyboard: false
  readonly property bool flattenScreenCorners: true
  readonly property bool exclusiveOpen: false

  // Container fits the content in BOTH dimensions — width capped at the
  // ControlCenter panel's width (440 × uiScaleRatio), height dynamic up
  // to 200. When the map needs less space, the panel shrinks.
  readonly property real contentPreferredWidth: Math.min(mapCanvas.maxPanelW, mapCanvas.renderedW + 16)
  readonly property real contentPreferredHeight: Math.min(200, mapCanvas.renderedH + 16)

  MapCanvas {
    id: mapCanvas
    anchors.fill: parent
    anchors.margins: 8
    screen: root.screen
  }
}
