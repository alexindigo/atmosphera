import Niri 1.0
import QtQuick
import "../../Helpers/BootstrapHandover.js" as BootstrapHandover
import "../../Helpers/NiriEdgeNavigation.js" as EdgeNavigation
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  property int floatingWindowPosition: Number.MAX_SAFE_INTEGER

  property ListModel workspaces: ListModel {}
  property var windows: []
  // niri's focused window id, or null. Window records carry no focus flag:
  // CompositorService derives every focus view from this one identity.
  property var focusedWindowId: null

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
  property var _bootstrapState: BootstrapHandover.create()
  property var _seedRetries: ({})

  Timer {
    id: seedRetryTimer
    interval: 250
    onTriggered: {
      var retries = root._seedRetries;
      root._seedRetries = ({});
      for (var name in retries) {
        var retry = retries[name];
        if (BootstrapHandover.canRetry(root._bootstrapState, retry.token))
          root.seedDomain(name, retry.request, retry.apply, retry.token.refresh);
      }
    }
  }

  // ── Gadget extractors (sever Qt ownership) ──

  function extractWindow(win) {
    var layout = win.layout || {};
    return {
      id: win.id,
      title: String(win.title || ""),
      appId: String(win.appId || ""),
      workspaceId: win.workspaceId || 0,
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
    refreshDerivedWindows();
    workspaceChanged();
  }

  function rebuildWindows(windowList) {
    var windowsList = [];
    var focused = null;
    for (var i = 0; i < windowList.length; i++) {
      var w = extractWindow(windowList[i]);
      resolveWindowOutput(w);
      windowsList.push(w);
      if (windowList[i].isFocused)
        focused = w.id;
    }
    windows = toSortedWindowList(windowsList);
    focusedWindowId = focused;
    windowListChanged();
    activeWindowChanged();
  }

  function resolveWindowOutput(win) {
    var ws = workspaceCache[win.workspaceId];
    win.output = (ws && ws.output) ? ws.output : "";
  }

  function refreshDerivedWindows(force) {
    // Cache arrival changes projections, never the live layout/focus facts.
    var projected = toSortedWindowList(windows.map(function (win) {
      var projected = Object.assign({}, win);
      projected.position = buildPosition(projected);
      resolveWindowOutput(projected);
      return projected;
    }));
    var changed = force || projected.some(function (win, index) {
      var previous = root.windows[index];
      return !previous || previous.id !== win.id || previous.output !== win.output || previous.position.x !== win.position.x || previous.position.y !== win.position.y;
    });
    if (!changed)
      return;
    windows = projected;
    windowListChanged();
  }

  function upsertWindow(winData) {
    var w = extractWindow(winData);
    resolveWindowOutput(w);
    // niri IPC: "If the window is focused, all other windows are no longer
    // focused." A newly opened focused window gets no WindowFocusChanged.
    if (winData.isFocused)
      focusedWindowId = w.id;
    else if (focusedWindowId === w.id)
      focusedWindowId = null;
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].id === w.id) {
        windows[i] = w;
        // New array identity: self-assignment of the same var array does
        // NOT emit the change notification, so bindings would never update
        windows = windows.slice();
        windowListChanged();
        activeWindowChanged();
        return;
      }
    }
    windows.push(w);
    windows = toSortedWindowList(windows);
    windowListChanged();
    activeWindowChanged();
  }

  function removeWindow(id) {
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].id === id) {
        windows.splice(i, 1);
        // New array identity so property bindings re-evaluate (see upsertWindow)
        windows = windows.slice();
        if (focusedWindowId === id)
          focusedWindowId = null;
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

  function seedDomain(name, request, apply, refresh) {
    var token = BootstrapHandover.begin(root._bootstrapState, name, refresh);
    if (!token)
      return;
    var reply = request();
    reply.finished.connect(function () {
      var outcome = BootstrapHandover.finish(root._bootstrapState, token, !reply.isError);
      if (outcome === "retry") {
        // The snapshot raced stream updates. Hydrate again only if the stream
        // has not supplied a full snapshot in the meantime.
        root.seedDomain(name, request, apply, refresh);
      } else if (outcome === "error") {
        Logger.w("NiriIpcBackend", name + " seed request failed:", reply.error.message);
        root._seedRetries[name] = {
          token: token,
          request: request,
          apply: apply
        };
        // Retry transport failures without a tight loop. Ownership, not a
        // retry quota, decides whether this work is still needed.
        if (NiriConnection.isConnected)
          seedRetryTimer.start();
      } else if (outcome === "accept") {
        apply(reply.value);
      }
    });
  }

  function bootstrap() {
    // Hydrate a late subscriber, then leave all changes to the event stream.
    seedDomain("windows", function () {
      return NiriRequests.windows();
    }, rebuildWindows);
    seedDomain("workspaces", function () {
      return NiriRequests.workspaces();
    }, rebuildWorkspaces);
    seedDomain("keyboardLayouts", function () {
      return NiriRequests.keyboardLayouts();
    }, updateKeyboardLayouts);

    // Outputs have no stream snapshot here; explicit refreshes keep latest-
    // request ownership and share the connection-lifetime guard.
    seedDomain("outputs", function () {
      return NiriRequests.outputs();
    }, function (outputs) {
      outputCache = {};
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
      refreshDerivedWindows();
      queryDisplayScales();
    }, true);
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
      BootstrapHandover.observe(root._bootstrapState, "windows", true);
      Logger.d("NiriIpcBackend", "onWindowsChanged:", windows.length, "windows");
      rebuildWindows(windows);
    }

    function onWorkspacesChanged(workspaces) {
      BootstrapHandover.observe(root._bootstrapState, "workspaces", true);
      Logger.d("NiriIpcBackend", "onWorkspacesChanged:", workspaces.length, "workspaces");
      rebuildWorkspaces(workspaces);
    }

    function onWindowOpenedOrChanged(window) {
      BootstrapHandover.observe(root._bootstrapState, "windows", false);
      upsertWindow(window);
    }

    function onWindowClosed(id) {
      BootstrapHandover.observe(root._bootstrapState, "windows", false);
      removeWindow(id);
    }

    function onWindowLayoutsChanged(changes) {
      BootstrapHandover.observe(root._bootstrapState, "windows", false);
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
        // Layout changes own new facts even when the derived order is stable.
        refreshDerivedWindows(true);
      }
    }

    function onWindowFocusChanged(id) {
      BootstrapHandover.observe(root._bootstrapState, "windows", false);
      // niriqml reports niri's "no focused window" (null id) as 0
      focusedWindowId = id ? id : null;
      activeWindowChanged();
    }

    function onWorkspaceActiveWindowChanged(workspaceId, windowId) {
      BootstrapHandover.observe(root._bootstrapState, "workspaces", false);
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
      BootstrapHandover.observe(root._bootstrapState, "workspaces", false);
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
      BootstrapHandover.observe(root._bootstrapState, "keyboardLayouts", true);
      updateKeyboardLayouts(layouts);
    }

    function onKeyboardLayoutSwitched(idx) {
      BootstrapHandover.observe(root._bootstrapState, "keyboardLayouts", false);
      onKeyboardSwitched(idx);
    }

    function onOverviewOpenedOrClosed(isOpen) {
      overviewActive = isOpen;
    }
  }

  Connections {
    target: NiriConnection

    function onConnectedChanged() {
      // Invalidate every pending callback on both sides of a reconnect.
      root._bootstrapState = BootstrapHandover.create();
      root._seedRetries = ({});
      seedRetryTimer.stop();
      // A new connection owns a new set of observations, not projections of
      // the last connection's rows while its replacement snapshot arrives.
      windows = [];
      focusedWindowId = null;
      workspaces.clear();
      workspaceCache = ({});
      outputCache = ({});
      keyboardLayouts = [];
      keyboardLayoutIndex = -1;
      overviewActive = false;
      windowListChanged();
      activeWindowChanged();
      workspaceChanged();
      if (NiriConnection.isConnected)
        bootstrap();
    }
  }

  Component.onCompleted: {
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

  property bool _edgeNavigationBusy: false

  // One navigation transaction at a time, with no stale repeat backlog. Native
  // replies have bounded timeouts. Handled acknowledges processing, not motion:
  // only the following authoritative snapshot can report a moved target.
  function navigateEdge(output, edge, requestId, completed) {
    if (_edgeNavigationBusy) {
      completed({
                  requestId: requestId,
                  outcome: "unknown"
                });
      return;
    }
    _edgeNavigationBusy = true;
    var finished = false;
    function finish(outcome) {
      if (finished)
        return;
      finished = true;
      root._edgeNavigationBusy = false;
      completed({
                  requestId: requestId,
                  outcome: outcome
                });
    }
    function receive(reply, consume) {
      reply.finished.connect(function () {
        if (reply.isError) {
          Logger.w("NiriIpcBackend", "Edge navigation failed:", reply.error.message);
          finish("error");
        } else {
          try {
            consume(reply.value);
          } catch (error) {
            Logger.w("NiriIpcBackend", "Edge navigation failed:", error);
            finish("error");
          }
        }
      });
    }
    function snapshot(consume) {
      receive(NiriRequests.workspaces(), function (workspaceList) {
        var snapshotWorkspaces = Array.from(workspaceList).map(root.extractWorkspace);
        receive(NiriRequests.windows(), function (windowList) {
          consume(snapshotWorkspaces, Array.from(windowList).map(root.extractWindow));
        });
      });
    }
    function navigate() {
      // Re-resolve after output focus, not from event-stream cache. Include the
      // actual trailing empty workspace, never an occupied-only projection.
      snapshot(function (workspaceList, windowList) {
        var target = EdgeNavigation.resolve(output, edge, workspaceList, windowList);
        if (target.kind !== "navigate") {
          finish(target.kind);
          return;
        }
        var actions = {
          left: "FocusColumnLeft",
          right: "FocusColumnRight",
          top: "FocusWorkspaceUp",
          bottom: "FocusWorkspaceDown"
        };
        var action = {};
        action[actions[edge]] = {};
        receive(NiriActions.sendAction(action), function () {
          snapshot(function (afterWorkspaces, afterWindows) {
            finish(EdgeNavigation.outcome(target, afterWorkspaces, afterWindows));
          });
        });
      });
    }
    try {
      receive(NiriRequests.workspaces(), function (workspaceList) {
        var focused = Array.from(workspaceList).find(function (ws) {
          return ws.isFocused;
        });
        if (focused && focused.output === output)
          navigate();
        else
          receive(NiriActions.sendAction({
                                           FocusMonitor: {
                                             output: output
                                           }
                                         }), navigate);
      });
    } catch (error) {
      Logger.w("NiriIpcBackend", "Edge navigation failed:", error);
      finish("error");
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
