import Niri 1.0
import QtQuick
import "../../Helpers/NiriEdgeNavigation.js" as EdgeNavigation
import "../../Helpers/NiriReply.js" as NiriReply
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // The module kept Niri 1.0 as its URI in 0.3.0; import success is not
  // evidence that the current-state and checked reply APIs exist.
  readonly property bool stateApiAvailable: typeof NiriState !== "undefined" && typeof NiriState.initialStateReceived === "boolean" && typeof NiriState.windowsSnapshot === "function"
  property bool ready: false
  readonly property real floatingWindowPosition: Number.MAX_SAFE_INTEGER

  // Keep the existing count/get backend contract without ListModel's
  // conversion of null optional roles to undefined or a type default.
  readonly property var workspaces: ({
                                       count: _workspaceRows.length,
                                       get: index => root._workspaceRows[index]
                                     })
  property var _workspaceRows: []
  property var windows: []
  property var focusedWindowId: null
  property var focusedWorkspaceId: null
  property bool overviewActive: false
  property var keyboardLayouts: []
  property int keyboardLayoutIndex: -1

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  property var outputCache: ({})
  property var workspaceCache: ({})
  property var _pendingReplies: new Map()
  property int _outputGeneration: 0
  property bool _edgeNavigationBusy: false

  Timer {
    id: outputRetry
    interval: 250
    onTriggered: root.bootstrap()
  }

  function scrollingOrdinals(value) {
    if (value == null || value.length !== 2)
      return [];
    const result = Array.from(value, ordinal => Number(ordinal));
    return result.every(ordinal => Number.isSafeInteger(ordinal) && ordinal > 0) ? result : [];
  }

  function extractWindow(win) {
    const layout = win.layout ?? {};
    const tilePosition = Array.from(layout.tilePosInWorkspaceView ?? []);
    return {
      id: win.id,
      title: win.title ?? "",
      appId: win.appId ?? "",
      workspaceId: win.workspaceId ?? null,
      isFloating: !!win.isFloating,
      isUrgent: !!win.isUrgent,
      pid: win.pid ?? null,
      output: "",
      position: win.isFloating ? {
                                   x: floatingWindowPosition,
                                   y: floatingWindowPosition
                                 } : {
        x: tilePosition[0] ?? 0,
        y: tilePosition[1] ?? 0
      },
      layout: {
        posInScrollingLayout: scrollingOrdinals(layout.posInScrollingLayout),
        tileSize: Array.from(layout.tileSize ?? []),
        windowSize: Array.from(layout.windowSize ?? []),
        tilePosInWorkspaceView: tilePosition,
        windowOffsetInTile: Array.from(layout.windowOffsetInTile ?? [])
      }
    };
  }

  function extractWorkspace(ws) {
    return {
      id: ws.id,
      idx: ws.idx,
      name: ws.name ?? "",
      output: ws.output ?? "",
      isFocused: !!ws.isFocused,
      isActive: !!ws.isActive,
      isUrgent: !!ws.isUrgent,
      activeWindowId: ws.activeWindowId ?? null,
      isOccupied: false
    };
  }

  function getWindowOutput(win) {
    return (workspaceCache[win.workspaceId]?.output ?? "") || null;
  }

  function toSortedWindowList(windowList) {
    return Array.from(windowList, win => {
      const ws = workspaceCache[win.workspaceId];
      const output = ws ? outputCache[ws.output] : null;
      return {
        win,
        idx: ws?.idx ?? 0,
        x: output?.x ?? 0,
        y: output?.y ?? 0
      };
    }).sort((a, b) => {
      const order = a.x - b.x || a.y - b.y || a.idx - b.idx || a.win.position.x - b.win.position.x || a.win.position.y - b.win.position.y;
      if (order)
        return order;
      const left = a.win.id;
      const right = b.win.id;
      return left.length - right.length || (left === right ? 0 : left < right ? -1 : 1);
    }).map(info => info.win);
  }

  function publishState() {
    const streamReady = stateApiAvailable && NiriConnection.isConnected && NiriState.initialStateReceived;
    const nextWindows = streamReady ? Array.from(NiriState.windowsSnapshot(), root.extractWindow) : [];
    const nextWorkspaces = streamReady ? Array.from(NiriState.workspacesSnapshot(), root.extractWorkspace) : [];
    const occupied = new Set(nextWindows.map(win => win.workspaceId));
    const cache = ({});
    for (const ws of nextWorkspaces) {
      ws.isOccupied = ws.activeWindowId !== null || occupied.has(ws.id);
      cache[ws.id] = ws;
    }
    for (const win of nextWindows)
      win.output = cache[win.workspaceId]?.output ?? "";

    const workspacesChanged = JSON.stringify(_workspaceRows) !== JSON.stringify(nextWorkspaces);
    if (workspacesChanged) {
      workspaceCache = cache;
      _workspaceRows = nextWorkspaces;
    }
    const sorted = toSortedWindowList(nextWindows);
    const windowsChanged = JSON.stringify(windows) !== JSON.stringify(sorted);
    const nextFocus = streamReady ? NiriState.focusedWindowId ?? null : null;
    const focusChanged = focusedWindowId !== nextFocus;
    if (windowsChanged)
      windows = sorted;
    focusedWindowId = nextFocus;
    focusedWorkspaceId = streamReady ? NiriState.focusedWorkspaceId ?? null : null;
    overviewActive = streamReady && NiriState.overviewOpen;
    updateKeyboardLayouts(streamReady ? NiriState.keyboardLayouts : null);
    ready = streamReady;

    if (workspacesChanged)
      workspaceChanged();
    if (windowsChanged)
      windowListChanged();
    if (focusChanged)
      activeWindowChanged();
  }

  function updateKeyboardLayouts(layouts) {
    const names = Array.from(layouts?.names ?? [], String);
    const index = layouts?.currentIdx ?? -1;
    if (index === keyboardLayoutIndex && JSON.stringify(keyboardLayouts) === JSON.stringify(names))
      return;
    keyboardLayouts = names;
    keyboardLayoutIndex = index;
    KeyboardLayoutService.setCurrentLayout(names[index] ?? "", names[0] ?? "");
  }

  function applyOutputs(outputs) {
    const cache = ({});
    for (const [name, output] of Object.entries(outputs)) {
      const logical = output.logical;
      const index = output.currentMode;
      const mode = index == null ? null : output.modes?.[index];
      cache[name] = {
        name: name,
        connected: true,
        scale: logical?.scale ?? 1,
        width: logical?.width ?? 0,
        height: logical?.height ?? 0,
        x: logical?.x ?? 0,
        y: logical?.y ?? 0,
        physical_width: output.physicalSize?.[0] ?? 0,
        physical_height: output.physicalSize?.[1] ?? 0,
        refresh_rate: mode?.refreshRate ?? 0,
        vrr_supported: !!output.vrrSupported,
        vrr_enabled: !!output.vrrEnabled,
        transform: logical?.transform?.wireName ?? ""
      };
    }
    outputCache = cache;
    publishState();
    queryDisplayScales();
  }

  function bootstrap() {
    if (!stateApiAvailable || !NiriConnection.isConnected)
      return;
    outputRetry.stop();
    const generation = ++_outputGeneration;
    NiriReply.observe(_pendingReplies, NiriRequests.outputs(), reply => {
      if (generation !== root._outputGeneration || !NiriConnection.isConnected)
        return;
      if (reply.isError) {
        Logger.w("NiriIpcBackend", "Outputs query failed:", reply.error.message);
        outputRetry.start();
      } else {
        root.applyOutputs(reply.value);
      }
    });
  }

  function initialize() {
    bootstrap();
  }
  function safeUpdateOutputs() {
    bootstrap();
  }
  function safeUpdateWorkspaces() {
    publishState();
  }
  function safeUpdateWindows() {
    publishState();
  }

  function queryDisplayScales() {
    CompositorService.onDisplayScalesUpdated(outputCache);
  }

  Connections {
    target: root.stateApiAvailable ? NiriState : null
    function onStateChanged() {
      root.publishState();
    }
  }

  Connections {
    target: root.stateApiAvailable ? NiriConnection : null
    function onConnectedChanged() {
      root._outputGeneration++;
      outputRetry.stop();
      root.outputCache = ({});
      root.publishState();
      root.queryDisplayScales();
      root.bootstrap();
    }
  }

  Component.onCompleted: {
    publishState();
    bootstrap();
  }
  Component.onDestruction: NiriReply.cancel(_pendingReplies)

  function handleAction(name, send) {
    if (!stateApiAvailable || !NiriConnection.isConnected)
      return;
    try {
      NiriReply.observe(_pendingReplies, send(), reply => {
        if (reply.isError)
          Logger.w("NiriIpcBackend", name + " failed:", reply.error.message);
      });
    } catch (error) {
      Logger.e("NiriIpcBackend", name + " failed:", error);
    }
  }

  function switchToWorkspace(workspace) {
    handleAction("switchToWorkspace", () => NiriActions.sendAction({
                                                                     FocusWorkspace: {
                                                                       reference: {
                                                                         Index: workspace.idx
                                                                       }
                                                                     }
                                                                   }));
  }
  function scrollWorkspaceContent(direction) {
    handleAction("scrollWorkspaceContent", () => NiriActions.sendAction(direction < 0 ? {
                                                                                          FocusColumnLeft: {}
                                                                                        } : {
                                                                          FocusColumnRight: {}
                                                                        }));
  }
  function focusWindow(win) {
    if (win?.id != null)
      handleAction("focusWindow", () => NiriActions.focusWindow(win.id));
  }
  function closeWindow(win) {
    if (win?.id != null)
      handleAction("closeWindow", () => NiriActions.closeWindow(win.id));
  }
  function turnOffMonitors() {
    handleAction("turnOffMonitors", () => NiriActions.sendAction({
                                                                   PowerOffMonitors: {}
                                                                 }));
  }
  function turnOnMonitors() {
    handleAction("turnOnMonitors", () => NiriActions.sendAction({
                                                                  PowerOnMonitors: {}
                                                                }));
  }
  function logout() {
    handleAction("logout", () => NiriActions.sendAction({
                                                          Quit: {
                                                            skip_confirmation: true
                                                          }
                                                        }));
  }
  function cycleKeyboardLayout() {
    handleAction("cycleKeyboardLayout", () => NiriActions.sendAction({
                                                                       SwitchLayout: {
                                                                         layout: "Next"
                                                                       }
                                                                     }));
  }
  function getFocusedScreen() {
    return null;
  }
  function spawn(command) {
    handleAction("spawn", () => NiriActions.spawn(command));
  }

  // Handled acknowledges processing, not motion. Compare a before/after query
  // pair and never use the stream cache to infer the effect of a request.
  function navigateEdge(output, edge, requestId, completed) {
    if (_edgeNavigationBusy || !ready) {
      completed({
                  requestId,
                  outcome: "unknown"
                });
      return;
    }
    _edgeNavigationBusy = true;
    let finished = false;
    function finish(outcome) {
      if (finished)
        return;
      finished = true;
      root._edgeNavigationBusy = false;
      completed({
                  requestId,
                  outcome
                });
    }
    function receive(reply, consume) {
      if (!NiriReply.observe(root._pendingReplies, reply, result => {
        if (result.isError) {
          Logger.w("NiriIpcBackend", "Edge navigation failed:", result.error.message);
          finish("error");
        } else {
          try {
            if (root.ready)
              consume(result.value);
            else
              finish("error");
          } catch (error) {
            Logger.w("NiriIpcBackend", "Edge navigation failed:", error);
            finish("error");
          }
        }
      }))
        finish("error");
    }
    function snapshot(consume) {
      receive(NiriRequests.workspaces(), workspaceList => {
        const rows = Array.from(workspaceList, root.extractWorkspace);
        receive(NiriRequests.windows(), windowList => consume(rows, Array.from(windowList, root.extractWindow)));
      });
    }
    function navigate() {
      snapshot((workspaceList, windowList) => {
        const target = EdgeNavigation.resolve(output, edge, workspaceList, windowList);
        if (target.kind !== "navigate") {
          finish(target.kind);
          return;
        }
        const actions = {
          left: "FocusColumnLeft",
          right: "FocusColumnRight",
          top: "FocusWorkspaceUp",
          bottom: "FocusWorkspaceDown"
        };
        const action = {};
        action[actions[edge]] = {};
        receive(NiriActions.sendAction(action), () => {
          snapshot((afterWorkspaces, afterWindows) => finish(EdgeNavigation.outcome(target, afterWorkspaces, afterWindows)));
        });
      });
    }
    try {
      receive(NiriRequests.workspaces(), workspaceList => {
        const focused = Array.from(workspaceList).find(ws => ws.isFocused);
        if (focused?.output === output)
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
}
