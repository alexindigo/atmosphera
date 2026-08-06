import Niri 1.0
import Niri 1.0
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
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
  // Terminal identity from Panel's bridge process: winId -> {cwd, fg, ...}.
  // When terminalIcons is on and the fg app resolves to a themed icon, the
  // tile shows the fg app's icon instead of the terminal's.
  property var terminalInfo: ({})
  property bool terminalIcons: true
  // Browser identity: winId -> {url, host, icon}. When browserIcons is on
  // and the bridge resolved a favicon, the tile shows the site favicon
  // instead of the browser's app icon.
  property var browserInfo: ({})
  property bool browserIcons: true
  // Audio attribution: winId -> {node, muted} for sounding windows.
  // Top-left speaker badge + top-right mute/unmute button when present.
  property var audioInfo: ({})
  property bool audioIndicators: true
  property real _userScale: 1.0

  // Emitted when a tile's mute button is clicked (NOT navigation — the
  // panel stays open regardless of hide-on-click)
  signal muteToggleRequested(int winId)
  // Emitted when a tile's play/pause button is clicked
  signal playToggleRequested(int winId)

  // ── Drag-to-move (DragHandler architecture) ──
  // The DragHandler owns the gesture; it takes the point over from the
  // Flickable, so drags and map-panning can't conflict. There is no
  // separate "armed" state: a drag BEGINS at the 300ms hold — at position
  // 0 (ghost at the press point) — and the handler continues it on move.
  property int _pressWinId: 0  // pressed candidate (also gates the model freeze)
  property real _pressTime: 0  // press timestamp for the pan-vs-drag decision
  property point _pressStart: Qt.point(0, 0)  // press point in mapContent (ghost's position 0)
  property int _dragWinId: 0
  property bool _dragging: false

  // The hold timer STARTS the drag (position 0): ghost appears, source
  // becomes an empty slot, others dim — before any movement
  Timer {
    id: pressHoldTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (root._pressWinId !== 0) {
        root._dragWinId = root._pressWinId;
        root._dragging = true;
      }
    }
  }
  // Phantom strip height — a FULL workspace-row-height box above the first
  // row (the insert-above drop target), per the design
  readonly property real _phantomH: _monH * _autoScale
  readonly property bool dragActive: root._dragging
  readonly property real phantomHeight: root._phantomH
  // The delegate + handler of the active drag (for centroid mapping)
  property var _activeDragDelegate: null
  property var _activeDragHandler: null

  function _cancelDrag() {
    _pressWinId = 0;
    _activeDragDelegate = null;
    _activeDragHandler = null;
    _dragWinId = 0;
    _dragging = false;
    pressHoldTimer.stop();
  }

  // Ghost center in mapContent coordinates: the handler's centroid while
  // the drag is moving, else the press point (position 0)
  readonly property point _ghostPos: {
    if (root._activeDragDelegate && root._activeDragHandler)
      return root._activeDragDelegate.mapToItem(mapContent, root._activeDragHandler.centroid.position.x, root._activeDragHandler.centroid.position.y);
    if (root._dragging)
      return root._pressStart;
    return Qt.point(0, 0);
  }

  // Workspace row under the ghost center. The phantom strip lives ABOVE the
  // content's top edge (ghostPos.y < 0 during a drag), so that's the
  // insert-above target; real rows sit in place beneath it (no shifting).
  readonly property int _dragTargetWs: {
    if (!root._dragging)
      return 0;
    var rowH = _monH * _autoScale;
    var stride = rowH + _rowGap;
    var order = workspaceOrder();
    var y = root._ghostPos.y;
    // Above the content's top edge = the phantom strip (grown panel area);
    // tolerate up to one row above the panel before calling it a miss
    if (y < 0)
      return (y > -rowH) ? -1 : 0;
    var slot = Math.floor(y / stride);
    if (slot >= order.length)
      slot = (y < order.length * stride + rowH) ? order.length - 1 : order.length;
    return (slot >= 0 && slot < order.length) ? order[slot].id : 0;
  }

  function _moveWindowToWorkspace(winId, wsId) {
    var idx = -1;
    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      var ws = CompositorService.workspaces.get(i);
      if (ws.id === wsId) {
        idx = ws.idx;
        break;
      }
    }
    if (idx < 0)
      return;
    moveWindowProcess.command = ["niri", "msg", "action", "move-window-to-workspace", String(idx), "--window-id", String(winId), "--focus", "false"];
    moveWindowProcess.running = true;
  }

  // Emulate "insert workspace above first" (no IPC for it): drop the window
  // on the trailing empty dynamic workspace, then reorder that workspace to
  // index 1 — niri's own reorder shifts everything else down. Two focus-free
  // ops, no window-level cascade (which niri's empty-ws removal breaks).
  function _insertAboveFirst(winId) {
    var trail = 1;
    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      var ws = CompositorService.workspaces.get(i);
      if (ws.idx > trail)
        trail = ws.idx;
    }
    insertProcess.command = ["sh", "-c", "niri msg action move-window-to-workspace " + trail + " --window-id " + winId + " --focus false && " + "niri msg action move-workspace-to-index 1 --reference " + trail];
    insertProcess.running = true;
  }

  Process {
    id: insertProcess
  }

  Process {
    id: moveWindowProcess
  }

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
  // Hovered tile's window id (0 = none) — drives the bottom-row info line
  property int hoveredWinId: 0
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
      hoveredWinId = 0;
    }
  }

  // One-line identity of the hovered tile's window, shown in the
  // always-empty trailing workspace row: app name + detail (terminal
  // cwd, browser host + page title, else window title)
  readonly property string _hoverInfoText: {
    if (hoveredWinId === 0)
      return "";
    var w = null;
    for (var i = 0; i < _windows.length; i++) {
      if (_windows[i].id === hoveredWinId) {
        w = _windows[i];
        break;
      }
    }
    if (!w)
      return "";
    var entry = ThemeIcons.findAppEntry(w.appId || "");
    var appName = entry ? (entry.name || w.appId) : (w.appId || "");
    var term = terminalInfo ? terminalInfo[w.id] : null;
    var brw = browserInfo ? browserInfo[w.id] : null;
    var detail = "";
    if (term && (term.cwdDisp || term.cwd))
      detail = term.cwdDisp || term.cwd;
    else if (brw && brw.host)
      detail = brw.host + (w.title ? " — " + w.title : "");
    else
      detail = w.title || "";
    return appName + (detail !== "" ? "  ·  " + detail : "");
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
  // Pure live view of laid-out windows (never frozen)
  readonly property var _windowsLive: {
    var all = (_backend && _backend.windows) ? _backend.windows : [];
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var lay = all[i].layout;
      if (lay && lay.posInScrollingLayout && lay.posInScrollingLayout.length)
        out.push(all[i]);
    }
    return out;
  }
  // Frozen snapshot while a gesture holds the mouse grab (delegate survival)
  property var _windowsCache: []
  // The map's view: frozen during press/drag, live otherwise. No read+write
  // of the cache inside this binding — that was a binding loop.
  readonly property var _windows: (root._pressWinId !== 0 || root._dragging) ? _windowsCache : _windowsLive

  // Keep the frozen snapshot current only while idle (no gesture)
  on_WindowsLiveChanged: {
    if (root._pressWinId === 0 && !root._dragging)
      root._windowsCache = _windowsLive;
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
      // distributes equally — EXCEPT during a drag, when the panel grows
      // upward for the phantom strip and the content stays bottom-anchored
      // (so the rows don't jump)
      x: Math.max(0, (flick.width - width * root._userScale) / 2)
      y: root._dragging ? Math.max(0, flick.height - height * root._userScale) : Math.max(0, (flick.height - height * root._userScale) / 2)
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

          // Drop-target outline while a drag hovers this row
          Rectangle {
            visible: root._dragging && modelData.id === root._dragTargetWs
            x: 0
            y: index * (root._monH * root._autoScale + root._rowGap)
            width: mapContent.width
            height: root._monH * root._autoScale
            color: Color.mPrimary
            opacity: 0.12
            border.color: Color.mPrimary
            border.width: 2
            z: 5
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
            cursorShape: Qt.PointingHandCursor
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
          // Hover includes the audio button corner: its MouseArea steals
          // hover events from hoverArea, but the cursor is still ON the tile
          readonly property bool _hovered: hoverArea.containsMouse || audioArea.containsMouse || playArea.containsMouse

          // If this tile dies mid-gesture (model churn), abort the drag
          // rather than leaving a stuck ghost/highlight behind
          Component.onDestruction: {
            if (root._pressWinId === modelData.id || root._dragWinId === modelData.id)
              root._cancelDrag();
          }

          // This tile is the one being dragged — render as an empty slot
          // (outline only) so it reads as "will move", not "will copy"
          readonly property bool _dragged: modelData.id === root._dragWinId && root._dragging

          // DRAG AFFORDANCE: while a drag runs (from the 300ms hold), every
          // tile except the source dims to ~55% so the dragged window
          // (empty slot + ghost) is unmistakable
          readonly property real _dragDim: (root._dragging && modelData.id !== root._dragWinId) ? 0.55 : 1.0

          // Total padding subtracted from the icon box: 8px/side on Large
          // tiles, 4px/side otherwise
          readonly property real _iconPad: root.sizeKey === "large" ? 16 : 8

          // Contrast glyph color derived from the tile's EFFECTIVE
          // background (tile color at its opacity, blended over the panel
          // surface): bright tile (green hover) -> dark glyph; dark tile
          // (blue focus, dim normal) -> light glyph
          function _lum(c) {
            return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
          }
          readonly property color _tileBg: _hovered ? Color.mTertiary : winColor
          readonly property real _tileBgOpacity: _hovered ? 1.0 : (modelData.isFocused ? 1.0 : (_secondary ? 0.3 : 0.15))
          readonly property real _bgLum: _tileBgOpacity * _lum(_tileBg) + (1 - _tileBgOpacity) * _lum(Color.mSurface)
          readonly property color _contrastColor: _bgLum > 0.5 ? Color.mSurface : Color.mOnSurface
          // Shared by the tile's corner buttons: 50% mOnTertiary preview
          readonly property color _onTertiaryHalf: Qt.rgba(Color.mOnTertiary.r, Color.mOnTertiary.g, Color.mOnTertiary.b, 0.5)

          // Icon selection: foreground-app icon for terminal tiles when the
          // bridge resolved one (and the setting allows), else the window's
          // own app icon. An unresolvable fg icon falls through to the app
          // icon via AtmoAppIcon's fallbackName — "if available" is automatic.
          readonly property var _term: root.terminalInfo ? root.terminalInfo[modelData.id] : null
          readonly property string _appIcon: ThemeIcons.iconNameForAppId(modelData.appId || "")
          readonly property string _fgIcon: (root.terminalIcons && _term && _term.fg) ? ThemeIcons.iconNameForAppId(_term.fg) : ""
          // Browser favicon (file path from the bridge's cache) wins over
          // app/fg icons when resolved; empty string means "no favicon"
          readonly property var _browser: root.browserInfo ? root.browserInfo[modelData.id] : null
          readonly property string _favicon: (root.browserIcons && _browser && _browser.icon) ? ("file://" + _browser.icon) : ""
          // Native favicon px (0 = unknown); the overlay never renders
          // larger than this — small cached icons stay crisp
          readonly property real _faviconW: (_browser && _browser.iconW) || 32
          // Audio attribution for this tile's window (null = not sounding
          // or not confidently attributed — no badges then)
          readonly property var _audio: root.audioInfo ? root.audioInfo[modelData.id] : null

          // Tile body. Hover replaces the color with tertiary at full
          // opacity, regardless of tier. While dragged it becomes an
          // empty outline slot (the ghost carries the window's identity).
          Rectangle {
            anchors.fill: parent
            color: winRect._dragged ? "transparent" : (winRect._hovered ? Color.mTertiary : winRect.winColor)
            opacity: winRect._dragDim * (winRect._dragged ? 1.0 : (winRect._hovered ? 1.0 : (modelData.isFocused ? 1.0 : (winRect._secondary ? 0.3 : 0.15))))
            Behavior on opacity {
              NumberAnimation {
                duration: 150
              }
            }
            border.color: winRect._dragged ? Color.mOutline : (winRect._hovered ? Color.mTertiary : winRect.winColor)
            border.width: winRect._dragged ? 1 : ((modelData.isFocused || winRect._secondary || winRect._hovered) ? 2 : 1)
          }

          // Base app icon (terminal fg-app or window app), with a rounded
          // chunk CUT OUT of its bottom-right corner while a site favicon
          // badge sits there. The wash shader stays on the inner icon; the
          // cutout mask lives on this wrapper (inverted MultiEffect mask).
          Item {
            id: iconWrap
            anchors.centerIn: parent
            // Square icon filling the tile with a uniform 4px padding on all
            // sides (sized from the tile's smaller dimension)
            width: Math.max(4, Math.min(parent.width, parent.height) - 8)
            height: width
            // Hide icons on tiles too small to read them — evaluated at the
            // rendered size, so zooming in (Ctrl+scroll) reveals icons as
            // they become readable; user setting hides them entirely
            visible: !root.hideIcons && !winRect._dragged && width * root._userScale >= 14
            opacity: (modelData.isFocused || winRect._hovered) ? 1.0 : 0.75

            // Badge rect (tile bottom-right, 2px margin) mapped into this
            // item's coordinate space for the cutout
            readonly property real _badgeX: (winRect.width - favBadge.width - 2) - x
            readonly property real _badgeY: (winRect.height - favBadge.height - 2) - y

            AtmoAppIcon {
              anchors.fill: parent
              name: winRect._fgIcon || winRect._appIcon
              fallbackName: winRect._appIcon
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

            // Cutout shape for the mask. Lives in place (MultiEffect needs
            // the item in-scene to capture it); hideSource keeps it off the
            // screen while the layer is active, and the rect's own visible
            // binding keeps it from painting when the layer is disabled
            // (non-browser tiles — an in-tree white rect would show).
            Item {
              id: cutoutMask
              anchors.fill: parent
              Rectangle {
                visible: favBadge.visible
                x: iconWrap._badgeX - 3
                y: iconWrap._badgeY - 3
                width: favBadge.width + 6
                height: favBadge.height + 6
                radius: 4
                color: "white"
              }
            }

            layer.enabled: favBadge.visible
            layer.effect: MultiEffect {
              maskEnabled: true
              maskInverted: true
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1.0
              maskSource: ShaderEffectSource {
                sourceItem: cutoutMask
                hideSource: true
              }
            }
          }

          // Site favicon for browser tiles — small badge anchored to the
          // tile's bottom-right corner, in the area cut out of the base
          // icon. Size is the smaller of 60% of the icon box and the
          // favicon's native resolution (clamped via the rendered scale),
          // so cached 32px icons stay crisp on huge tiles.
          Image {
            id: favBadge
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            readonly property real _box: Math.max(4, Math.min(parent.width, parent.height) - 8)
            width: Math.max(4, Math.min(_box * 0.6, winRect._faviconW / root._userScale))
            height: width
            visible: !root.hideIcons && !winRect._dragged && winRect._favicon !== "" && iconWrap.visible
            opacity: (modelData.isFocused || winRect._hovered) ? 1.0 : 0.75
            source: winRect._favicon
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            sourceSize: Qt.size(width, height)

            layer.enabled: !(modelData.isFocused || winRect._hovered)
            layer.effect: ShaderEffect {
              property color targetColor: Color.mOnSurface
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
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: {
              root.hoverEnter(modelData.workspaceId);
              root.hoveredWinId = modelData.id;
            }
            onExited: {
              root.hoveredWinId = 0;
              root.hoverExit();
            }
            onPressed: mouse => {
              // Record press position/time; start the hold timer that will
              // BEGIN the drag (position 0) at 300ms
              root._cancelDrag();
              if (mouse.button === Qt.LeftButton) {
                root._pressTime = Date.now();
                root._pressWinId = modelData.id;
                root._pressStart = mapToItem(mapContent, mouse.x, mouse.y);
                dragH.enabled = true;
                pressHoldTimer.restart();
              }
            }
            onReleased: {
              root._pressWinId = 0;
              pressHoldTimer.stop();
              // Held long enough to start the drag but never moved → the
              // handler never activated: cancel, no drop, no navigation
              if (root._dragging && !root._activeDragHandler)
                root._cancelDrag();
            }
            onClicked: function (mouse) {
              // A drag that the DragHandler consumed never reaches here —
              // the handler's takeover cancels the MouseArea's press
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

          // The drag itself: ALWAYS enabled so it activates on any
          // press+move (enabling mid-press doesn't work — the handler only
          // arms for presses that START while enabled). Long-press is a
          // DECISION made at activation: grab too early (< 300ms) and we
          // deactivate, handing the gesture back to the Flickable as a map
          // pan; grab at/after 300ms and it's a real tile drag.
          DragHandler {
            id: dragH
            acceptedButtons: Qt.LeftButton
            target: null
            onActiveChanged: {
              if (dragH.active) {
                var heldMs = Date.now() - root._pressTime;
                if (heldMs < 300) {
                  // Too early — this is a map pan, not a tile drag. Hand
                  // the gesture back to the Flickable; next press re-arms.
                  dragH.enabled = false;
                  root._pressWinId = 0;
                  pressHoldTimer.stop();
                  return;
                }
                // Drag already running (started at the hold timer); claim
                // the handler for centroid tracking
                root._activeDragDelegate = winRect;
                root._activeDragHandler = dragH;
                root._pressWinId = 0;
              } else {
                if (root._dragWinId === modelData.id) {
                  // Phantom strip = insert-above-first; a real row = plain
                  // move; no target = cancel
                  if (root._dragTargetWs === -1)
                    root._insertAboveFirst(modelData.id);
                  else if (root._dragTargetWs !== 0 && root._dragTargetWs !== modelData.workspaceId)
                    root._moveWindowToWorkspace(modelData.id, root._dragTargetWs);
                  root._activeDragDelegate = null;
                  root._activeDragHandler = null;
                  root._dragWinId = 0;
                  root._dragging = false;
                }
              }
            }
          }

          // Play/pause button — top-left corner, mirrors the mute button.
          // Only shown when the window has a controllable MPRIS player
          Item {
            id: playButton
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.top: parent.top
            anchors.topMargin: 2
            readonly property real _box: Math.max(4, Math.min(parent.width, parent.height) - 8)
            width: Math.max(5, _box * 0.33)
            height: width
            visible: root.audioIndicators && !winRect._dragged && !!winRect._audio && !!winRect._audio.player && iconWrap.visible

            AtmoIcon {
              anchors.fill: parent
              icon: (winRect._audio && winRect._audio.playing) ? Icon.mediaPause : Icon.mediaPlay
              pointSize: Math.max(5, playButton._box * 0.33)
              applyUiScale: false
              color: playArea.containsMouse ? Color.mOnTertiary : ((winRect._hovered || modelData.isFocused) ? winRect._onTertiaryHalf : winRect._contrastColor)
              opacity: (modelData.isFocused || winRect._hovered) ? 1.0 : 0.75

              layer.enabled: !(modelData.isFocused || winRect._hovered)
              layer.effect: ShaderEffect {
                property color targetColor: Color.mOnSurface
                property real colorizeMode: 4.0
                property real blendStrength: 0.0
                property real hueAdjustment: 0.0
                fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
              }
            }

            MouseArea {
              id: playArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton
              onEntered: {
                root.hoverEnter(modelData.workspaceId);
                root.hoveredWinId = modelData.id;
              }
              onExited: {
                root.hoveredWinId = 0;
                root.hoverExit();
              }
              onClicked: root.playToggleRequested(modelData.id)
            }
          }

          // Audio indicator — combined state-icon + mute button at the
          // tile's top-right. Declared AFTER hoverArea so its MouseArea
          // wins clicks in its corner (clicking it must never focus the
          // window or close the panel). Icon shows stream state and flips
          // on mute, so the action is always reversible.
          Item {
            id: audioButton
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.top: parent.top
            anchors.topMargin: 2
            readonly property real _box: Math.max(4, Math.min(parent.width, parent.height) - 8)
            width: Math.max(5, _box * 0.33)
            height: width
            visible: root.audioIndicators && !winRect._dragged && !!winRect._audio && iconWrap.visible

            AtmoIcon {
              anchors.fill: parent
              icon: (winRect._audio && winRect._audio.muted) ? Icon.volumeMute : Icon.volumeHigh
              pointSize: Math.max(5, audioButton._box * 0.33)
              applyUiScale: false
              // Icon hover -> mOnTertiary full; active/hovered tile ->
              // same color at 50% opacity (softer preview of the armed
              // state); otherwise luminance-derived contrast
              color: audioArea.containsMouse ? Color.mOnTertiary : ((winRect._hovered || modelData.isFocused) ? winRect._onTertiaryHalf : winRect._contrastColor)
              opacity: (modelData.isFocused || winRect._hovered) ? 1.0 : 0.75

              layer.enabled: !(modelData.isFocused || winRect._hovered)
              layer.effect: ShaderEffect {
                property color targetColor: Color.mOnSurface
                property real colorizeMode: 4.0
                property real blendStrength: 0.0
                property real hueAdjustment: 0.0
                fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
              }
            }

            MouseArea {
              id: audioArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton
              // Feed the workspace hover-band counter just like the tile's
              // own area, so crossing tile<->button doesn't flicker the band
              onEntered: {
                root.hoverEnter(modelData.workspaceId);
                root.hoveredWinId = modelData.id;
              }
              onExited: {
                root.hoveredWinId = 0;
                root.hoverExit();
              }
              onClicked: root.muteToggleRequested(modelData.id)
            }
          }
        }
      }

      // Drag ghost: follows the cursor while a window is being dragged to
      // another workspace. Semi-transparent chip with the window's icon.
      Item {
        id: dragGhost
        visible: root._dragging
        readonly property var _win: {
          for (var i = 0; i < root._windows.length; i++) {
            if (root._windows[i].id === root._dragWinId)
              return root._windows[i];
          }
          return null;
        }
        width: Math.max(32, 240 * root._autoScale)
        height: width * 0.7
        x: root._ghostPos.x - width / 2
        y: root._ghostPos.y - height / 2
        z: 100

        Rectangle {
          anchors.fill: parent
          radius: 6
          color: Color.mSurface
          border.color: Color.mPrimary
          border.width: 2
          opacity: 0.92
        }
        AtmoAppIcon {
          anchors.centerIn: parent
          width: Math.max(12, parent.height - 12)
          height: width
          name: dragGhost._win ? ThemeIcons.iconNameForAppId(dragGhost._win.appId || "") : "application-x-executable"
        }
      }

      // Hover info line — centered in the trailing workspace row (niri's
      // dynamic workspaces guarantee it exists and never has windows)
      NText {
        readonly property int _lastSlot: Math.max(0, root.workspaceOrder().length - 1)
        readonly property real _rowH: root._monH * root._autoScale
        visible: root._hoverInfoText !== ""
        text: root._hoverInfoText
        color: Color.mOnSurfaceVariant
        pointSize: Math.max(1, _rowH * 0.3)
        width: Math.min(implicitWidth, mapContent.width - 16)
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        anchors.horizontalCenter: mapContent.horizontalCenter
        y: _lastSlot * (root._monH * root._autoScale + root._rowGap) + (_rowH - implicitHeight) / 2
        z: 90
      }
    }
  }

  // Phantom "insert above first workspace" strip — rendered at the TOP of
  // the panel's content area, above the map. During a drag the panel grows
  // upward by _phantomH (Panel.qml) and the map content bottom-anchors, so
  // the strip appears above the rows without moving them.
  Item {
    id: phantomRow
    visible: root._dragging
    x: 0
    y: 0
    width: root.width
    height: root._phantomH
    z: 100

    // Soft band — clearly visible, brighter when it's the drop target
    Rectangle {
      anchors.fill: parent
      color: Color.mPrimary
      opacity: root._dragTargetWs === -1 ? 0.32 : 0.16
      Behavior on opacity {
        NumberAnimation {
          duration: 120
        }
      }
    }
    // Bright line at the very top edge
    Rectangle {
      x: 0
      y: 0
      width: parent.width
      height: 2
      color: Color.mPrimary
      opacity: root._dragTargetWs === -1 ? 1.0 : 0.6
    }
    // Left indicator bar (same as real rows)
    Rectangle {
      x: 0
      y: 0
      width: root._barWidth
      height: parent.height
      color: Color.mPrimary
      opacity: root._dragTargetWs === -1 ? 1.0 : 0.6
    }
  }

  NText {
    visible: root._windows.length === 0
    anchors.centerIn: parent
    text: "No windows"
    color: Color.mOnSurfaceVariant
  }
}
