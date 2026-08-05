import Niri 1.0
import Niri 1.0
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

// Spatial niri overview map, streaming directly from CompositorService.niriBackend.
// Uniform layout model (per NiriWindowsLayout.drawio):
//  - every workspace row is a monH-tall slot, rows strided contiguously
//  - row contents (indicator bar + windows) are inset _rowInset px top/bottom,
//    so any two adjacent rows' contents are exactly _rowGap px apart
//  - within a row, each column's tiles scale proportionally to fill the inset
//    extent with _winGap px between tiles; columns are _colGap px apart
//  - 4px indicator bar + 4px gap at each row's left edge
// Helpers work in raw canvas units; ALL gaps are applied in screen px after
// _autoScale (canvas-unit gaps would shrink to nothing at map scale).
Item {
  id: root

  property var screen: null
  // When true, app icons are not drawn on tiles (user setting)
  property bool hideIcons: false
  property real _userScale: 1.0

  // Emitted only when the user NAVIGATES via the map (tile focus click,
  // workspace-row click, context-menu Focus). Other interactions (context
  // menu open/close, zoom, drag, close-window) deliberately do NOT emit —
  // the hide-on-click setting keys off this signal.
  signal navigationRequested
  readonly property real _monH: screen ? screen.height : 960
  // Workspace under the mouse (0 = none) — drives the hover row band.
  // _hoverCount tracks how many hover areas currently hold the cursor
  // (tile areas and row areas overlap) so exits can't clear the band while
  // another area still holds it — enter/exit ordering between stacked
  // MouseAreas is not guaranteed.
  property int hoveredWs: 0
  property int _hoverCount: 0

  function hoverEnter(wsId) {
    _hoverCount++;
    hoveredWs = wsId;
  }

  function hoverExit() {
    _hoverCount--;
    if (_hoverCount <= 0) {
      _hoverCount = 0;
      hoveredWs = 0;
    }
  }

  // Delegates may be destroyed while hovered (panel close) — reset
  onVisibleChanged: {
    if (!visible) {
      _hoverCount = 0;
      hoveredWs = 0;
    }
  }

  // Authoritative "cursor is over the widget" signal — independent of the
  // stacked tile/row MouseAreas (which don't reliably emit every exit, so
  // the counter can stick). blocking: false, so child areas keep working.
  HoverHandler {
    id: mapHover
    onHoveredChanged: {
      if (!hovered) {
        root._hoverCount = 0;
        root.hoveredWs = 0;
      }
    }
  }

  // Bumped on workspace changes so bindings that read the workspace
  // ListModel imperatively re-evaluate (ListModel reads aren't tracked).
  property int _wsRev: 0

  readonly property real _winGap: 1 // between stacked tiles within a column
  readonly property real _colGap: 2 // between columns
  readonly property real _rowGap: 2 // between workspace rows (slot stride = monH + _rowGap)
  readonly property real _barWidth: 4
  readonly property real _leftInset: 12 // 4px bar + 8px gap before the first column

  readonly property var _backend: CompositorService.niriBackend
  // Windows that can be placed in the scrolling layout (skips floating etc.)
  readonly property var _windows: {
    var all = (_backend && _backend.windows) ? _backend.windows : [];
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var lay = all[i].layout;
      if (lay && lay.posInScrollingLayout && lay.posInScrollingLayout.length)
        out.push(all[i]);
    }
    return out;
  }

  Connections {
    target: CompositorService
    function onWorkspaceChanged() {
      root._wsRev++;
    }
  }

  // ── Workspaces ──

  // All workspaces sorted by niri idx, including empty ones
  function workspaceOrder() {
    _wsRev; // imperative-refresh dependency
    var list = [];
    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      var ws = CompositorService.workspaces.get(i);
      list.push({
                  id: ws.id,
                  idx: ws.idx
                });
    }
    // Fallback: workspaces that have windows but aren't in the model
    for (var j = 0; j < _windows.length; j++) {
      var wsId = _windows[j].workspaceId;
      var found = false;
      for (var k = 0; k < list.length; k++) {
        if (list[k].id === wsId) {
          found = true;
          break;
        }
      }
      if (!found)
        list.push({
                    id: wsId,
                    idx: 9999
                  });
    }
    list.sort(function (a, b) {
      return a.idx - b.idx;
    });
    return list;
  }

  // Row index of a workspace within workspaceOrder
  function workspaceSlotIndex(wsId) {
    var order = workspaceOrder();
    for (var i = 0; i < order.length; i++) {
      if (order[i].id === wsId)
        return i;
    }
    return 0;
  }

  // Active window of a workspace (niri's Workspace.active_window_id)
  function activeWindowId(wsId) {
    _wsRev; // imperative-refresh dependency
    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      var ws = CompositorService.workspaces.get(i);
      if (ws.id === wsId)
        return ws.activeWindowId || 0;
    }
    return 0;
  }

  // ── Column geometry (canvas units) ──

  // Per-row max tile heights for one column: {row: height}
  function columnRowHeights(wsId, col) {
    var rowH = {};
    for (var i = 0; i < _windows.length; i++) {
      var w = _windows[i];
      if (w.workspaceId !== wsId)
        continue;
      var lay = w.layout;
      if (lay.posInScrollingLayout[0] !== col)
        continue;
      var r = lay.posInScrollingLayout[1] || 0;
      var th = (lay.tileSize && lay.tileSize[1]) || 0;
      if (rowH[r] === undefined || th > rowH[r])
        rowH[r] = th;
    }
    return rowH;
  }

  // Max tile width among windows of one column
  function columnMaxWidth(wsId, col) {
    var max = 0;
    for (var i = 0; i < _windows.length; i++) {
      var w = _windows[i];
      if (w.workspaceId !== wsId)
        continue;
      var lay = w.layout;
      if (lay.posInScrollingLayout[0] !== col)
        continue;
      var tw = (lay.tileSize && lay.tileSize[0]) || 0;
      if (tw > max)
        max = tw;
    }
    return max;
  }

  // X offset of a column = sum of max widths of all columns left of it
  function columnX(wsId, col) {
    var cols = [];
    for (var i = 0; i < _windows.length; i++) {
      var w = _windows[i];
      if (w.workspaceId !== wsId)
        continue;
      var c = w.layout.posInScrollingLayout[0];
      if (c < col && cols.indexOf(c) === -1)
        cols.push(c);
    }
    var x = 0;
    for (var j = 0; j < cols.length; j++) {
      x += columnMaxWidth(wsId, cols[j]);
    }
    return x;
  }

  // Number of columns left of this one (drives the inter-column gap)
  function colCountLeft(wsId, col) {
    var cols = [];
    for (var i = 0; i < _windows.length; i++) {
      var w = _windows[i];
      if (w.workspaceId !== wsId)
        continue;
      var c = w.layout.posInScrollingLayout[0];
      if (c < col && cols.indexOf(c) === -1)
        cols.push(c);
    }
    return cols.length;
  }

  // Sum of tile heights above this row within its column (canvas units)
  function tileY(wsId, col, row) {
    var rowH = columnRowHeights(wsId, col);
    var y = 0;
    for (var key in rowH) {
      if (Number(key) < row)
        y += rowH[key];
    }
    return y;
  }

  // Number of tiles above this one in its column (drives the intra-column gap)
  function tileCountAbove(wsId, col, row) {
    var rowH = columnRowHeights(wsId, col);
    var n = 0;
    for (var key in rowH) {
      if (Number(key) < row)
        n++;
    }
    return n;
  }

  // Uniform proportional fill: factor that scales a column's tiles so they
  // fill the row's inset extent exactly, with _winGap px between tiles
  function columnScale(wsId, col) {
    var rowH = columnRowHeights(wsId, col);
    var n = 0, sum = 0;
    for (var key in rowH) {
      n++;
      sum += rowH[key];
    }
    if (n === 0 || sum <= 0)
      return 1.0;
    var avail = _monH * _autoScale - (n - 1) * _winGap;
    if (avail <= 0)
      return 0.05;
    return avail / (sum * _autoScale);
  }

  // Position (workspace + column) of the globally focused window — defines
  // the "active column" whose windows get the secondary highlight.
  // Focus id comes from NiriState (C++ singleton, handles WorkspaceActivated
  // semantics natively); we only scan our window array to locate its tile.
  function focusedWindowPos() {
    var fid = NiriState.focusedWindowId;
    if (fid === 0)
      return null;
    for (var i = 0; i < _windows.length; i++) {
      if (_windows[i].id === fid) {
        return {
          ws: _windows[i].workspaceId,
          col: _windows[i].layout.posInScrollingLayout[0]
        };
      }
    }
    return null;
  }

  // DEBUG: verify current-workspace detection
  on_WsRevChanged: {
    var dump = [];
    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      var ws = CompositorService.workspaces.get(i);
      dump.push(ws.id + (ws.isFocused ? "*" : "") + (ws.isActive ? "+" : ""));
    }
    Logger.w("MapCanvas", "wsRev=" + _wsRev + " currentWs=" + NiriState.focusedWorkspaceId + " focusedWin=" + NiriState.focusedWindowId + " flags: " + dump.join(" "));
  }
  Component.onCompleted: _wsRevChanged()

  // ── Canvas extent (raw canvas units; horizontal gaps reserved separately) ──

  readonly property real _canvasW: {
    var max = 0;
    for (var i = 0; i < _windows.length; i++) {
      var w = _windows[i];
      var col = w.layout.posInScrollingLayout[0];
      var right = columnX(w.workspaceId, col) + columnMaxWidth(w.workspaceId, col);
      if (right > max)
        max = right;
    }
    return max > 0 ? max : 100;
  }
  readonly property real _canvasH: {
    var n = workspaceOrder().length;
    return n > 0 ? n * _monH : _monH;
  }

  readonly property real _maxColsInRow: {
    var perWs = {};
    for (var i = 0; i < _windows.length; i++) {
      var w = _windows[i];
      var c = w.layout.posInScrollingLayout[0];
      if (!perWs[w.workspaceId])
        perWs[w.workspaceId] = [];
      if (perWs[w.workspaceId].indexOf(c) === -1)
        perWs[w.workspaceId].push(c);
    }
    var m = 0;
    for (var k in perWs) {
      if (perWs[k].length > m)
        m = perWs[k].length;
    }
    return m;
  }
  readonly property real _gapsW: _leftInset + Math.max(0, _maxColsInRow - 1) * _colGap
  readonly property real _gapsH: Math.max(0, workspaceOrder().length - 1) * _rowGap

  readonly property real _autoScale: {
    if (_canvasW <= 0 || _canvasH <= 0)
      return 1.0;
    return Math.min((root.width - _gapsW) / _canvasW, (root.height - _gapsH) / _canvasH);
  }

  // Panel size limits: the panel shrinks to fit the content in BOTH
  // dimensions up to these caps — they are limits, not the size.
  // Width matches the ControlCenter panel (440 × uiScaleRatio).
  property real maxPanelW: Math.round(440 * Style.uiScaleRatio)
  property real maxPanelH: 200
  readonly property real _panelMargin: 8

  // Scale that fits the whole map within the limits — may exceed 1.0 so
  // content also EXPANDS to fill the box when it's smaller than the limits
  readonly property real fitScale: {
    if (_canvasW <= 0 || _canvasH <= 0)
      return 1.0;
    var s = Math.min((maxPanelW - 2 * _panelMargin - _gapsW) / _canvasW, (maxPanelH - 2 * _panelMargin - _gapsH) / _canvasH);
    return s > 0 ? s : 1.0;
  }
  // What the map actually renders at that scale (before panel margins)
  readonly property real renderedW: _canvasW * fitScale + _gapsW
  readonly property real renderedH: _canvasH * fitScale + _gapsH

  // Single shared context menu instance
  MapWindowContextMenu {
    id: contextMenu
    // Focus from the menu is navigation too; Close is not
    onNavigationRequested: root.navigationRequested()
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: mapContent.width * root._userScale
    contentHeight: mapContent.height * root._userScale
    interactive: true

    WheelHandler {
      acceptedModifiers: Qt.ControlModifier
      onWheel: function (wheel) {
        var oldScale = root._userScale;
        root._userScale = Math.min(2.0, Math.max(0.1, root._userScale * (1 + wheel.angleDelta.y * 0.001)));
        flick.contentX += wheel.point.position.x * flick.contentWidth * (root._userScale - oldScale) / oldScale;
        flick.contentY += wheel.point.position.y * flick.contentHeight * (root._userScale - oldScale) / oldScale;
      }
    }

    Item {
      id: mapContent
      width: root._canvasW * root._autoScale + root._gapsW
      height: root._canvasH * root._autoScale + root._gapsH
      // Center within the Flickable viewport so any residual letterbox
      // distributes equally
      x: Math.max(0, (flick.width - width * root._userScale) / 2)
      y: Math.max(0, (flick.height - height * root._userScale) / 2)
      scale: root._userScale
      transformOrigin: Item.TopLeft

      // Workspace row indicator bars: 4px strip at each row's left edge,
      // full slot height. Rows stride monH + _rowGap, so bars keep exactly
      // _rowGap px between them — uniform across all rows.
      // Focused = primary, rest = outline.
      Repeater {
        model: root.workspaceOrder()

        Item {
          // Row band — hover feedback only (no always-on highlight; the
          // current workspace is marked by the indicator bar alone)
          Rectangle {
            visible: modelData.id === root.hoveredWs
            x: 0
            y: index * (root._monH * root._autoScale + root._rowGap)
            width: mapContent.width
            height: root._monH * root._autoScale
            color: Color.mPrimary
            opacity: 0.07
            z: -1
          }

          // Row indicator bar
          Rectangle {
            x: 0
            y: index * (root._monH * root._autoScale + root._rowGap)
            width: root._barWidth
            height: root._monH * root._autoScale
            color: modelData.id === NiriState.focusedWorkspaceId ? Color.mPrimary : Color.mOutline
            z: 10
          }

          // Row area not covered by tiles: hover drives the band, left
          // click switches to that workspace (including empty ones).
          MouseArea {
            x: 0
            y: index * (root._monH * root._autoScale + root._rowGap)
            width: mapContent.width
            height: root._monH * root._autoScale
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onEntered: root.hoverEnter(modelData.id)
            onExited: root.hoverExit()
            onClicked: {
              CompositorService.switchToWorkspace(modelData);
              root.navigationRequested();
            }
          }
        }
      }

      Repeater {
        model: root._windows

        Item {
          id: winRect

          readonly property var _lay: modelData.layout
          readonly property int _col: _lay.posInScrollingLayout[0]
          readonly property int _row: _lay.posInScrollingLayout[1] || 0
          readonly property int _wsSlot: root.workspaceSlotIndex(modelData.workspaceId)
          readonly property real _colScale: root.columnScale(modelData.workspaceId, _col)
          // Active window of this workspace (niri's per-workspace
          // active_window_id) — always shown; it's the "current window of
          // that row" marker, independent of which workspace is focused.
          readonly property bool _activeInWs: modelData.id === root.activeWindowId(modelData.workspaceId)
          readonly property bool _inActiveCol: {
            var fp = root.focusedWindowPos();
            return fp !== null && modelData.workspaceId === fp.ws && _col === fp.col;
          }
          // Secondary tier: active window of a non-focused workspace, or any
          // window in the focused window's column. The focused window itself
          // always keeps the primary tier.
          readonly property bool _secondary: !modelData.isFocused && (_activeInWs || _inActiveCol)

          // Position: row slot top (stride monH + _rowGap) + proportional
          // tile offset within the column
          x: root.columnX(modelData.workspaceId, _col) * root._autoScale + root._leftInset + root.colCountLeft(modelData.workspaceId, _col) * root._colGap
          y: _wsSlot * (root._monH * root._autoScale + root._rowGap) + root.tileY(modelData.workspaceId, _col, _row) * root._autoScale * _colScale + root.tileCountAbove(modelData.workspaceId, _col, _row) * root._winGap
          width: Math.max(root.columnMaxWidth(modelData.workspaceId, _col) * root._autoScale, 4)
          height: Math.max(((_lay.tileSize && _lay.tileSize[1]) || 50) * root._autoScale * _colScale, 2)

          // Visual hierarchy: urgent (mError) > focused global (primary,
          // strongest fill) > secondary (active in workspace or in active
          // column) > normal
          readonly property color winColor: modelData.isUrgent ? Color.mError : (_secondary ? Color.mSecondary : Color.mPrimary)
          readonly property bool _hovered: hoverArea.containsMouse

          // Tile body. Hover replaces the color with tertiary at full
          // opacity, regardless of tier.
          Rectangle {
            anchors.fill: parent
            color: winRect._hovered ? Color.mTertiary : winRect.winColor
            opacity: winRect._hovered ? 1.0 : (modelData.isFocused ? 1.0 : (winRect._secondary ? 0.3 : 0.15))
            border.color: winRect._hovered ? Color.mTertiary : winRect.winColor
            border.width: (modelData.isFocused || winRect._secondary || winRect._hovered) ? 2 : 1
          }

          // App icon overlay: washed-out monochrome mask (luminance alpha,
          // mOnSurface) at 75% opacity — EXCEPT on the focused tile and on
          // hover, where it renders full color at full opacity (shader off).
          AtmoAppIcon {
            anchors.centerIn: parent
            // Square icon filling the tile with a uniform 4px padding on all
            // sides (sized from the tile's smaller dimension)
            width: Math.max(4, Math.min(parent.width, parent.height) - 8)
            height: width
            // Hide icons on tiles too small to read them — evaluated at the
            // rendered size, so zooming in (Ctrl+scroll) reveals icons as
            // they become readable; user setting hides them entirely
            visible: !root.hideIcons && width * root._userScale >= 14
            opacity: (modelData.isFocused || winRect._hovered) ? 1.0 : 0.75
            name: ThemeIcons.iconNameForAppId(modelData.appId || "")
            smooth: true

            layer.enabled: !(modelData.isFocused || winRect._hovered)
            layer.effect: ShaderEffect {
              property color targetColor: Color.mOnSurface
              // Mask mode (4.0): flat washed-out color, alpha from luminance —
              // dark icon backgrounds vanish, every icon reads as a uniform
              // soft watermark regardless of its original colors
              property real colorizeMode: 4.0
              property real blendStrength: 0.0
              property real hueAdjustment: 0.0
              fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
            }
          }

          MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: root.hoverEnter(modelData.workspaceId)
            onExited: root.hoverExit()
            onClicked: function (mouse) {
              if (mouse.button === Qt.LeftButton) {
                CompositorService.focusWindow({
                                                id: modelData.id
                                              });
                root.navigationRequested();
              } else if (mouse.button === Qt.RightButton) {
                contextMenu.windowData = modelData;
                contextMenu.open();
              }
            }
          }
        }
      }
    }
  }

  NText {
    visible: root._windows.length === 0
    anchors.centerIn: parent
    text: "No windows"
    color: Color.mOnSurfaceVariant
  }
}
