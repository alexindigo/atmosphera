import Niri 1.0
import QtQuick
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  property int floatingWindowPosition: Number.MAX_SAFE_INTEGER

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  property bool overviewActive: false

  property var keyboardLayouts: []
  property int keyboardLayoutIndex: -1

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  property var outputCache: ({})
  property var workspaceCache: ({})

  property bool _warned: false

  // ── Gadget extractors (sever Qt ownership) ──

  function extractWindow(win) {
    var layout = win.layout || {};
    return {
      id: win.id,
      title: String(win.title || ""),
      appId: String(win.appId || ""),
      workspaceId: win.workspaceId || 0,
      isFocused: win.isFocused,
      isFloating: win.isFloating || false,
      isUrgent: win.isUrgent || false,
      pid: win.pid || 0,
      output: "",
      position: buildPosition(win),
      layout: {
        posInScrollingLayout: layout.posInScrollingLayout ? Array.from(layout.posInScrollingLayout) : [],
        tileSize: layout.tileSize ? Array.from(layout.tileSize) : [],
        windowSize: layout.windowSize ? Array.from(layout.windowSize) : [],
        tilePosInWorkspaceView: layout.tilePosInWorkspaceView ? Array.from(layout.tilePosInWorkspaceView) : [],
        windowOffsetInTile: layout.windowOffsetInTile ? Array.from(layout.windowOffsetInTile) : []
      }
    };
  }

  function buildPosition(win) {
    if (win.isFloating) {
      return {
        x: floatingWindowPosition,
        y: floatingWindowPosition
      };
    }
    var layout = win.layout;
    var tilePos = layout && layout.tilePosInWorkspaceView ? layout.tilePosInWorkspaceView : [];
    if (tilePos.length >= 2) {
      return {
        x: tilePos[0],
        y: tilePos[1]
      };
    }
    return {
      x: 0,
      y: 0
    };
  }

  function extractWorkspace(ws) {
    return {
      id: ws.id,
      idx: ws.idx,
      name: String(ws.name || ""),
      output: String(ws.output || ""),
      isFocused: ws.isFocused,
      isActive: ws.isActive,
      isUrgent: ws.isUrgent,
      activeWindowId: ws.activeWindowId || 0,
      isOccupied: ws.isOccupied !== undefined ? ws.isOccupied : (ws.activeWindowId !== 0 || false)
    };
  }

  // ── Workspace / window state builders ──

  function rebuildWorkspaces(workspaceList) {
    workspaceCache = {};
    workspaces.clear();
    for (var i = 0; i < workspaceList.length; i++) {
      var ws = extractWorkspace(workspaceList[i]);
      workspaces.append(ws);
      workspaceCache[ws.id] = ws;
    }
    workspaceChanged();
  }

  function rebuildWindows(windowList) {
    var windowsList = [];
    for (var i = 0; i < windowList.length; i++) {
      var w = extractWindow(windowList[i]);
      resolveWindowOutput(w);
      windowsList.push(w);
    }
    windows = toSortedWindowList(windowsList);
    safeUpdateFocusedWindow();
    windowListChanged();
    activeWindowChanged();
  }

  function resolveWindowOutput(win) {
    var ws = workspaceCache[win.workspaceId];
    win.output = (ws && ws.output) ? ws.output : "";
  }

  function upsertWindow(winData) {
    var w = extractWindow(winData);
    resolveWindowOutput(w);
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].id === w.id) {
        windows[i] = w;
        // New array identity: self-assignment of the same var array does
        // NOT emit the change notification, so bindings would never update
        windows = windows.slice();
        safeUpdateFocusedWindow();
        windowListChanged();
        activeWindowChanged();
        return;
      }
    }
    windows.push(w);
    windows = toSortedWindowList(windows);
    safeUpdateFocusedWindow();
    windowListChanged();
    activeWindowChanged();
  }

  function removeWindow(id) {
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].id === id) {
        windows.splice(i, 1);
        // New array identity so property bindings re-evaluate (see upsertWindow)
        windows = windows.slice();
        safeUpdateFocusedWindow();
        windowListChanged();
        activeWindowChanged();
        return;
      }
    }
  }

  // ── Sort / query helpers ──

  function getWindowOutput(win) {
    var ws = workspaceCache[win.workspaceId];
    return (ws && ws.output) ? ws.output : null;
  }

  function toSortedWindowList(windowList) {
    return windowList.map(function (win) {
      var ws = workspaceCache[win.workspaceId];
      var output = (ws && ws.output) ? outputCache[ws.output] : null;
      return {
        window: win,
        workspaceIdx: ws ? ws.idx : 0,
        outputX: output ? output.x : 0,
        outputY: output ? output.y : 0
      };
    }).sort(function (a, b) {
      if (a.outputX !== b.outputX)
        return a.outputX - b.outputX;
      if (a.outputY !== b.outputY)
        return a.outputY - b.outputY;
      if (a.workspaceIdx !== b.workspaceIdx)
        return a.workspaceIdx - b.workspaceIdx;
      if (a.window.position.x !== b.window.position.x)
        return a.window.position.x - b.window.position.x;
      if (a.window.position.y !== b.window.position.y)
        return a.window.position.y - b.window.position.y;
      return a.window.id - b.window.id;
    }).map(function (info) {
      return info.window;
    });
  }

  function safeUpdateFocusedWindow() {
    focusedWindowIndex = -1;
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].isFocused) {
        focusedWindowIndex = i;
        break;
      }
    }
  }

  // ── Keyboard layout helpers ──

  function updateKeyboardLayouts(layouts) {
    if (!layouts)
      return;
    keyboardLayouts = layouts.names ? Array.from(layouts.names).map(String) : [];
    keyboardLayoutIndex = layouts.currentIdx;

    var idx = layouts.currentIdx;
    var names = keyboardLayouts;
    var currentName = (idx >= 0 && idx < names.length) ? names[idx] : "";
    var fallback = (names.length > 0) ? names[0] : "";

    KeyboardLayoutService.setCurrentLayout(currentName, fallback);
    Logger.d("NiriService", "Keyboard layouts updated:", names.join(","));
  }

  function onKeyboardSwitched(idx) {
    keyboardLayoutIndex = idx;
    var names = keyboardLayouts;
    var currentName = (idx >= 0 && idx < names.length) ? names[idx] : "";
    var fallback = (names.length > 0) ? names[0] : "";
    KeyboardLayoutService.setCurrentLayout(currentName, fallback);
  }

  // ── Output / bootstrap ──

  function bootstrap() {
    // Query keyboard layouts
    var klReply = NiriRequests.keyboardLayouts();
    klReply.finished.connect(function () {
      if (klReply.isError) {
        Logger.w("NiriIpcBackend", "keyboardLayouts request failed:", klReply.error.message);
        return;
      }
      updateKeyboardLayouts(klReply.value);
    });

    // Query outputs
    var outReply = NiriRequests.outputs();
    outReply.finished.connect(function () {
      if (outReply.isError) {
        Logger.w("NiriIpcBackend", "outputs request failed:", outReply.error.message);
        return;
      }
      outputCache = {};
      var outputs = outReply.value;
      var keys = Object.keys(outputs);
      for (var i = 0; i < keys.length; i++) {
        var name = keys[i];
        var output = outputs[name];
        var logical = output.logical || {};
        var mode = output.currentMode >= 0 && output.modes ? (output.modes[output.currentMode] || {}) : {};
        outputCache[name] = {
          "name": name,
          "connected": true,
          "scale": logical.scale || 1.0,
          "width": logical.width || 0,
          "height": logical.height || 0,
          "x": logical.x || 0,
          "y": logical.y || 0,
          "physical_width": output.physicalSize ? output.physicalSize[0] || 0 : 0,
          "physical_height": output.physicalSize ? output.physicalSize[1] || 0 : 0,
          "refresh_rate": mode.refreshRate || 0,
          "vrr_supported": output.vrrSupported || false,
          "vrr_enabled": output.vrrEnabled || false,
          "transform": logical.transform || ""
        };
      }
      queryDisplayScales();
    });
  }

  function initialize() {
    bootstrap();
  }

  function queryDisplayScales() {
    if (CompositorService && CompositorService.onDisplayScalesUpdated) {
      CompositorService.onDisplayScalesUpdated(outputCache);
    }
  }

  // ── Signal subscriptions ──

  Connections {
    target: NiriEvents

    function onWindowsChanged(windows) {
      Logger.d("NiriIpcBackend", "onWindowsChanged:", windows.length, "windows");
      rebuildWindows(windows);
    }

    function onWorkspacesChanged(workspaces) {
      Logger.d("NiriIpcBackend", "onWorkspacesChanged:", workspaces.length, "workspaces");
      rebuildWorkspaces(workspaces);
    }

    function onWindowOpenedOrChanged(window) {
      upsertWindow(window);
    }

    function onWindowClosed(id) {
      removeWindow(id);
    }

    function onWindowLayoutsChanged(changes) {
      // niri emits layout-only updates (tile moves/resizes) via this event,
      // NOT WindowOpenedOrChanged — update layouts in place so consumers
      // (e.g. the overview map) stay in sync on every move
      var updated = false;
      for (var i = 0; i < changes.length; i++) {
        var pair = changes[i];
        if (!pair || pair.length < 2)
          continue;
        var id = pair[0];
        var lay = pair[1];
        for (var j = 0; j < windows.length; j++) {
          if (windows[j].id === id) {
            windows[j].layout = {
              posInScrollingLayout: lay.pos_in_scrolling_layout ? Array.from(lay.pos_in_scrolling_layout) : [],
              tileSize: lay.tile_size ? Array.from(lay.tile_size) : [],
              windowSize: lay.window_size ? Array.from(lay.window_size) : [],
              tilePosInWorkspaceView: lay.tile_pos_in_workspace_view ? Array.from(lay.tile_pos_in_workspace_view) : [],
              windowOffsetInTile: lay.window_offset_in_tile ? Array.from(lay.window_offset_in_tile) : []
            };
            updated = true;
            break;
          }
        }
      }
      if (updated) {
        // New array identity so property bindings re-evaluate (see upsertWindow)
        windows = windows.slice();
        windowListChanged();
      }
    }

    function onWindowFocusChanged(id) {
      for (var i = 0; i < windows.length; i++) {
        windows[i].isFocused = (windows[i].id === id);
      }
      // New array identity so property bindings re-evaluate (see upsertWindow)
      windows = windows.slice();
      safeUpdateFocusedWindow();
      activeWindowChanged();
    }

    function onWorkspaceActiveWindowChanged(workspaceId, windowId) {
      // Update a single workspace's active window in place (no full rebuild)
      for (var i = 0; i < workspaces.count; i++) {
        if (workspaces.get(i).id === workspaceId) {
          workspaces.setProperty(i, "activeWindowId", windowId);
          break;
        }
      }
      var cached = workspaceCache[workspaceId];
      if (cached)
        cached.activeWindowId = windowId;
      workspaceChanged();
    }

    function onWorkspaceActivated(workspaceId, focused) {
      // niri does NOT resend WorkspacesChanged on activation — apply the
      // event incrementally instead of re-querying (reactive, no round-trip):
      // per IPC spec, the activated workspace becomes active on its output
      // (all others on that output become inactive), and when focused=true
      // it becomes the single focused workspace globally.
      var targetWs = workspaceCache[workspaceId];
      var targetOutput = targetWs ? targetWs.output : "";
      for (var i = 0; i < workspaces.count; i++) {
        var ws = workspaces.get(i);
        if (ws.output === targetOutput) {
          var nowActive = (ws.id === workspaceId);
          if (ws.isActive !== nowActive)
            workspaces.setProperty(i, "isActive", nowActive);
        }
        if (focused) {
          var nowFocused = (ws.id === workspaceId);
          if (ws.isFocused !== nowFocused)
            workspaces.setProperty(i, "isFocused", nowFocused);
        }
      }
      // Keep the internal cache in sync
      for (var id in workspaceCache) {
        var c = workspaceCache[id];
        if (c.output === targetOutput)
          c.isActive = (c.id === workspaceId);
        if (focused)
          c.isFocused = (c.id === workspaceId);
      }
      workspaceChanged();
    }

    function onKeyboardLayoutsChanged(layouts) {
      updateKeyboardLayouts(layouts);
    }

    function onKeyboardLayoutSwitched(idx) {
      onKeyboardSwitched(idx);
    }

    function onOverviewOpenedOrClosed(isOpen) {
      overviewActive = isOpen;
    }
  }

  Connections {
    target: NiriConnection

    function onConnectedChanged() {
      if (NiriConnection.isConnected)
        bootstrap();
    }
  }

  Component.onCompleted: {
    // Seed current state with one-shot queries. The event stream's initial
    // WindowsChanged/WorkspacesChanged snapshot is dispatched exactly once at
    // connection time — if this backend armed after it (startup race against
    // the NiriService Loader), we'd otherwise stay empty until enough live
    // events trickle in. The queries return the same gadget payloads the
    // live signals deliver, so the rebuild paths are identical.
    var winsReply = NiriRequests.windows();
    winsReply.finished.connect(function () {
      if (winsReply.isError) {
        Logger.w("NiriIpcBackend", "windows seed request failed:", winsReply.error.message);
        return;
      }
      rebuildWindows(winsReply.value);
    });
    var wsReply = NiriRequests.workspaces();
    wsReply.finished.connect(function () {
      if (wsReply.isError) {
        Logger.w("NiriIpcBackend", "workspaces seed request failed:", wsReply.error.message);
        return;
      }
      rebuildWorkspaces(wsReply.value);
    });
    if (NiriConnection.isConnected)
      bootstrap();
  }

  // ── Actions ──

  function switchToWorkspace(workspaceData) {
    try {
      var reply = NiriActions.sendAction({
                                           FocusWorkspace: {
                                             reference: {
                                               Index: workspaceData.idx
                                             }
                                           }
                                         });
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "switchToWorkspace failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to switch workspace:", e);
    }
  }

  function scrollWorkspaceContent(direction) {
    try {
      var action = direction < 0 ? {
                                     FocusColumnLeft: {}
                                   } : {
        FocusColumnRight: {}
      };
      var reply = NiriActions.sendAction(action);
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "scrollWorkspaceContent failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to scroll workspace content:", e);
    }
  }

  function focusWindow(win) {
    try {
      var reply = NiriActions.focusWindow(win.id);
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "focusWindow failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to focus window:", e);
    }
  }

  function closeWindow(win) {
    try {
      var reply = NiriActions.closeWindow(win.id);
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "closeWindow failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to close window:", e);
    }
  }

  function turnOffMonitors() {
    try {
      var reply = NiriActions.sendAction({
                                           PowerOffMonitors: {}
                                         });
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "turnOffMonitors failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to turn off monitors:", e);
    }
  }

  function turnOnMonitors() {
    try {
      var reply = NiriActions.sendAction({
                                           PowerOnMonitors: {}
                                         });
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "turnOnMonitors failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to turn on monitors:", e);
    }
  }

  function logout() {
    try {
      var reply = NiriActions.sendAction({
                                           Quit: {
                                             skip_confirmation: true
                                           }
                                         });
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "logout failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    try {
      var reply = NiriActions.sendAction({
                                           SwitchLayout: {
                                             layout: "Next"
                                           }
                                         });
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "cycleKeyboardLayout failed:", reply.error.message);
      });
    } catch (e) {
      Logger.e("NiriService", "Failed to cycle keyboard layout:", e);
    }
  }

  function getFocusedScreen() {
    return null;
  }

  function spawn(command) {
    try {
      var reply = NiriActions.spawn(command);
      reply.finished.connect(function () {
        if (reply.isError)
          Logger.w("NiriIpcBackend", "spawn failed:", reply.error.message);
      });
      Logger.d("NiriService", "spawn:", command.join(" "));
    } catch (e) {
      Logger.e("NiriService", "Failed to spawn command:", e);
    }
  }
}
