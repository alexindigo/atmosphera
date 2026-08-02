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
      isOccupied: ws.activeWindowId !== 0 || false
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
        windows = windows;
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
        windows = windows;
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

    function onWindowFocusChanged(id) {
      for (var i = 0; i < windows.length; i++) {
        windows[i].isFocused = (windows[i].id === id);
      }
      windows = windows;
      safeUpdateFocusedWindow();
      activeWindowChanged();
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
