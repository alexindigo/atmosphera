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
  signal statePublished

  property var outputCache: ({})
  property var workspaceCache: ({})
  property var _pendingReplies: new Map()
  property int _outputGeneration: 0
  property int _peerGeneration: 0
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
    const nextWorkspaceFocus = streamReady ? NiriState.focusedWorkspaceId ?? null : null;
    const nextOverview = streamReady && NiriState.overviewOpen;
    const publicationChanged = workspacesChanged || windowsChanged || focusChanged || focusedWorkspaceId !== nextWorkspaceFocus || overviewActive !== nextOverview || ready !== streamReady;
    if (windowsChanged)
      windows = sorted;
    focusedWindowId = nextFocus;
    focusedWorkspaceId = nextWorkspaceFocus;
    overviewActive = nextOverview;
    updateKeyboardLayouts(streamReady ? NiriState.keyboardLayouts : null);
    ready = streamReady;

    if (publicationChanged)
      statePublished();
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
    CompositorService.onDisplayScalesUpdated(cache);
  }

  function bootstrap() {
    if (!stateApiAvailable || !NiriConnection.isConnected)
      return;
    outputRetry.stop();
    const generation = ++_outputGeneration;
    const current = () => generation === root._outputGeneration && NiriConnection.isConnected;
    request("Outputs query", () => NiriRequests.outputs(), (ok, error, value) => {
      if (!current())
        return;
      if (!ok)
        outputRetry.start();
      else
        root.applyOutputs(value);
    }, current);
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
    bootstrap();
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
      root._peerGeneration++;
      root._outputGeneration++;
      outputRetry.stop();
      root.outputCache = ({});
      root.publishState();
      root.bootstrap();
    }
  }

  Component.onCompleted: {
    publishState();
    bootstrap();
  }
  Component.onDestruction: NiriReply.cancel(_pendingReplies)

  // An operation that derives actions from stream state keeps one guard for
  // every step, even if a request socket survives an event-stream reconnect.
  function currentStateGuard() {
    const generation = _peerGeneration;
    return () => root.ready && NiriConnection.isConnected && generation === root._peerGeneration;
  }

  function request(name, send, completed, current) {
    function fail(message) {
      Logger.w("NiriIpcBackend", name + " failed:", message);
      if (completed)
        completed(false, message);
    }
    if (!stateApiAvailable || (current && !current())) {
      fail("IPC unavailable");
      return;
    }
    let reply;
    try {
      reply = send();
    } catch (error) {
      fail(String(error));
      return;
    }
    if (!NiriReply.observe(_pendingReplies, reply, result => {
      if (current && !current())
        fail("IPC state retired");
      else if (result.isError)
        fail(result.error.message);
      else if (completed)
        completed(true, "", result.value);
    }))
      fail("IPC returned no reply");
  }

  function handleStateAction(name, send, completed) {
    request(name, send, completed, currentStateGuard());
  }

  function workspaceForId(id) {
    return ready && typeof id === "string" ? _workspaceRows.find(row => row.id === id) ?? null : null;
  }

  function windowForId(id) {
    return ready && typeof id === "string" ? windows.find(row => row.id === id) ?? null : null;
  }

  function switchToWorkspace(workspace) {
    if (workspaceForId(workspace?.id))
      handleStateAction("switchToWorkspace", () => NiriActions.focusWorkspace({
                                                                                Id: workspace.id
                                                                              }));
  }
  function scrollWorkspaceContent(direction) {
    handleStateAction("scrollWorkspaceContent", () => NiriActions.sendAction(direction < 0 ? {
                                                                                               FocusColumnLeft: {}
                                                                                             } : {
                                                                               FocusColumnRight: {}
                                                                             }));
  }
  function focusWindow(win) {
    if (windowForId(win?.id))
      handleStateAction("focusWindow", () => NiriActions.focusWindow(win.id));
  }
  function closeWindow(win) {
    if (windowForId(win?.id))
      handleStateAction("closeWindow", () => NiriActions.closeWindow(win.id));
  }

  // An insert moves into a live empty workspace first. Never reorder on a
  // rejected move, across stream generations, or on an unconfirmed move.
  function moveWindowToWorkspace(windowId, workspaceId, completed, insertAtIndex) {
    const done = typeof completed === "function" ? completed : () => {};
    const window = windowForId(windowId);
    const workspace = workspaceForId(workspaceId);
    const insert = insertAtIndex != null;
    if (!window || !workspace || window.workspaceId === workspaceId || (insert && (workspace.isOccupied || !Number.isSafeInteger(insertAtIndex) || insertAtIndex < 1))) {
      done(false, "Invalid or stale move target");
      return;
    }
    const reference = {
      Id: workspaceId
    };
    const current = currentStateGuard();
    request("moveWindowToWorkspace", () => NiriActions.moveWindowToWorkspace(windowId, reference, false), (ok, error) => {
      if (!ok || !insert) {
        done(ok, error);
        return;
      }
      root.request("Confirm insert membership", () => NiriRequests.windows(), (ok, error, rows) => {
        if (!ok) {
          done(false, error);
          return;
        }
        if (!root.workspaceForId(workspaceId) || !Array.from(rows).some(win => win.id === windowId && win.workspaceId === workspaceId)) {
          done(false, "Window did not reach the target workspace");
          return;
        }
        root.request("moveWorkspaceToIndex", () => NiriActions.moveWorkspaceToIndex(String(insertAtIndex), reference), done, current);
      }, current);
    }, current);
  }
  function turnOffMonitors() {
    request("turnOffMonitors", () => NiriActions.sendAction({
                                                              PowerOffMonitors: {}
                                                            }));
  }
  function turnOnMonitors() {
    request("turnOnMonitors", () => NiriActions.sendAction({
                                                             PowerOnMonitors: {}
                                                           }));
  }
  function logout() {
    request("logout", () => NiriActions.sendAction({
                                                     Quit: {
                                                       skip_confirmation: true
                                                     }
                                                   }));
  }
  function cycleKeyboardLayout() {
    request("cycleKeyboardLayout", () => NiriActions.sendAction({
                                                                  SwitchLayout: {
                                                                    layout: "Next"
                                                                  }
                                                                }));
  }
  function getFocusedScreen() {
    return null;
  }
  function spawn(command) {
    // This action uses no stream state. NiriQml owns endpoint cancellation.
    request("spawn", () => NiriActions.spawn(command));
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
    const current = currentStateGuard();
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
    function receive(send, consume) {
      root.request("Edge navigation", send, (ok, error, value) => {
        if (!ok) {
          finish("error");
          return;
        }
        try {
          consume(value);
        } catch (error) {
          Logger.w("NiriIpcBackend", "Edge navigation failed:", error);
          finish("error");
        }
      }, current);
    }
    function snapshot(consume) {
      receive(() => NiriRequests.workspaces(), workspaceList => {
        const rows = Array.from(workspaceList, root.extractWorkspace);
        receive(() => NiriRequests.windows(), windowList => consume(rows, Array.from(windowList, root.extractWindow)));
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
        receive(() => NiriActions.sendAction(action), () => {
          snapshot((afterWorkspaces, afterWindows) => finish(EdgeNavigation.outcome(target, afterWorkspaces, afterWindows)));
        });
      });
    }
    receive(() => NiriRequests.workspaces(), workspaceList => {
      const focused = Array.from(workspaceList).find(ws => ws.isFocused);
      if (focused?.output === output)
        navigate();
      else
        receive(() => NiriActions.sendAction({
                                               FocusMonitor: {
                                                 output: output
                                               }
                                             }), navigate);
    });
  }
}
