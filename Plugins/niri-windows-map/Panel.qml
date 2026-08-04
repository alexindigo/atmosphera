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

  // Size preset from plugin settings (compact/regular/large). These are
  // LIMITS, not fixed sizes — the panel still shrinks to fit the content.
  readonly property var _sizePreset: {
    var s = pluginApi?.pluginSettings?.panelSize || "regular";
    if (s === "large")
      return {
        w: Math.round(880 * Style.uiScaleRatio),
        h: 400
      };
    if (s === "compact")
      return {
        w: Math.round(300 * Style.uiScaleRatio),
        h: 200
      };
    return {
      w: Math.round(440 * Style.uiScaleRatio),
      h: 200
    };
  }

  // Container fits the content in BOTH dimensions — capped by the size
  // preset. When the map needs less space, the panel shrinks.
  readonly property real contentPreferredWidth: Math.min(_sizePreset.w, mapCanvas.renderedW + 16)
  readonly property real contentPreferredHeight: Math.min(_sizePreset.h, mapCanvas.renderedH + 16)

  MapCanvas {
    id: mapCanvas
    anchors.fill: parent
    anchors.margins: 8
    screen: root.screen
    maxPanelW: root._sizePreset.w
    maxPanelH: root._sizePreset.h
  }
}
