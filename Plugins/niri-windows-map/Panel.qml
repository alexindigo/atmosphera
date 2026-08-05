import QtQuick
import Quickshell.Io
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

  // Single position value — the slot derives its SmartPanel anchors from
  // this one string (same pattern as ControlCenter/Dock/Launcher), so all
  // four anchor reads stay consistent. Bottom-right is the default.
  readonly property string corner: pluginApi?.pluginSettings?.corner || "bottomRight"

  // SmartPanel behavior opt-outs (passed through by the slot)
  readonly property bool dimEnabled: false
  readonly property bool closeOnClickOutside: false
  readonly property bool exclusiveKeyboard: false
  readonly property bool flattenScreenCorners: true
  readonly property bool exclusiveOpen: false

  // Terminal identity bridge: winId -> {cwd, cwdBase, fg, fgCmd} for
  // terminal windows, resolved by the python helper from /proc.
  readonly property bool terminalIcons: pluginApi?.pluginSettings?.terminalIcons ?? true
  property var terminalInfo: ({})
  readonly property string _bridgePath: Qt.resolvedUrl("terminal-bridge.py").toString().replace("file://", "")

  Process {
    id: terminalBridge
    // Only poll while the map is actually open and the feature is on
    running: root.visible && root.terminalIcons
    command: ["python3", root._bridgePath]
    onRunningChanged: {
      if (!running)
        root.terminalInfo = ({});
    }
    stdout: SplitParser {
      onRead: data => {
        try {
          const arr = JSON.parse(data);
          const m = {};
          for (const e of arr)
            m[e.winId] = e;
          root.terminalInfo = m;
        } catch (err) {
          // partial line — ignore
        }
      }
    }
  }

  // Browser identity bridge: winId -> {url, host, icon} for browser
  // windows, resolved locally from browser history + favicon caches.
  readonly property bool browserIcons: pluginApi?.pluginSettings?.browserIcons ?? true
  property var browserInfo: ({})

  // Audio attribution: winId -> {node, muted} for windows confidently
  // matched to a live output stream (sticky cache in AudioMap)
  readonly property bool audioIndicators: pluginApi?.pluginSettings?.audioIndicators ?? true

  AudioMap {
    id: audioMap
    // NOT tied to root.visible: the sticky stream↔window cache must stay
    // warm while the map is closed, or pairs formed during the
    // single-stream era are lost before the map ever opens
    active: root.audioIndicators
  }

  readonly property string _browserBridgePath: Qt.resolvedUrl("browser-bridge.py").toString().replace("file://", "")

  Process {
    id: browserBridge
    running: root.visible && root.browserIcons
    command: ["python3", root._browserBridgePath]
    onRunningChanged: {
      if (!running)
        root.browserInfo = ({});
    }
    stdout: SplitParser {
      onRead: data => {
        try {
          const arr = JSON.parse(data);
          const m = {};
          for (const e of arr)
            m[e.winId] = e;
          root.browserInfo = m;
        } catch (err) {
          // partial line — ignore
        }
      }
    }
  }

  // Size preset from plugin settings (compact/regular/large). Each is a
  // FIXED bounding box; content uniform-fits inside without scrolling.
  //   compact = 300 x 300
  //   regular = Control Center width x 50% of screen height
  //   large   = 50% of screen w x 70% of screen h
  readonly property string _sizeKey: pluginApi?.pluginSettings?.panelSize || "regular"
  readonly property real _screenW: root.screen?.width || 1920
  readonly property real _screenH: root.screen?.height || 1080
  readonly property var _sizePreset: {
    if (_sizeKey === "large")
      return {
        w: Math.round(_screenW * 0.5),
        h: Math.round(_screenH * 0.7)
      };
    if (_sizeKey === "compact")
      return {
        w: Math.round(300 * Style.uiScaleRatio),
        h: Math.round(300 * Style.uiScaleRatio)
      };
    // regular: Control Center width x 50% of screen height
    return {
      w: Math.round(440 * Style.uiScaleRatio),
      h: Math.round(_screenH * 0.5)
    };
  }

  // Bounding box is the UPPER LIMIT; the visible panel hugs the content
  // so aspect-mismatch never leaves letterbox gaps around the map.
  readonly property real contentPreferredWidth: Math.min(_sizePreset.w, mapCanvas.renderedW + 16)
  readonly property real contentPreferredHeight: Math.min(_sizePreset.h, mapCanvas.renderedH + 16)

  // DEBUG: measure the sizing chain
  on_SizePresetChanged: Logger.w("NiriMapPanel", "preset=" + JSON.stringify(_sizePreset) + " contentPrefW=" + contentPreferredWidth + " contentPrefH=" + contentPreferredHeight + " renderedW=" + mapCanvas.renderedW.toFixed(1) + " renderedH=" + mapCanvas.renderedH.toFixed(1) + " fitScale=" + mapCanvas.fitScale.toFixed(4))
  Component.onCompleted: Qt.callLater(function () {
    root._sizePresetChanged();
  })

  MapCanvas {
    id: mapCanvas
    anchors.fill: parent
    anchors.margins: 8
    screen: root.screen
    maxPanelW: root._sizePreset.w
    maxPanelH: root._sizePreset.h
    hideIcons: pluginApi?.pluginSettings?.hideIcons ?? false
    terminalIcons: root.terminalIcons
    terminalInfo: root.terminalInfo
    browserIcons: root.browserIcons
    browserInfo: root.browserInfo
    audioIndicators: root.audioIndicators
    audioInfo: audioMap.audioInfo
    onMuteToggleRequested: winId => audioMap.toggleMute(winId)
    onPlayToggleRequested: winId => audioMap.togglePlay(winId)
    // Hide after navigation only (tile focus / workspace switch / menu
    // Focus) — future interactions (drag, zoom, menu Close) won't hide
    onNavigationRequested: {
      if (pluginApi?.pluginSettings?.hideOnClick)
        pluginApi.closePanel(root.screen);
    }
  }
}
