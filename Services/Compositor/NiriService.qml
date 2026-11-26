import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  readonly property bool available: loader.status === Loader.Ready && loader.item.stateApiAvailable
  readonly property bool moduleMissing: loader.status === Loader.Error

  readonly property real floatingWindowPosition: Number.MAX_SAFE_INTEGER

  property var _emptyModel: ListModel {}

  readonly property var workspaces: available ? loader.item.workspaces : _emptyModel
  readonly property var windows: available ? loader.item.windows : []
  readonly property var focusedWindowId: available ? loader.item.focusedWindowId : null
  readonly property var focusedWorkspaceId: available ? loader.item.focusedWorkspaceId : null
  readonly property bool ready: available && loader.item.ready

  readonly property bool overviewActive: available ? loader.item.overviewActive : false
  readonly property var keyboardLayouts: available ? loader.item.keyboardLayouts : []

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged
  signal statePublished

  readonly property var outputCache: available ? loader.item.outputCache : ({})
  readonly property var workspaceCache: available ? loader.item.workspaceCache : ({})

  Loader {
    id: loader
    active: CompositorService.isNiri
    source: "NiriIpcBackend.qml"
    onLoaded: {
      // Forward inner backend signals
      if (item.stateApiAvailable) {
        item.statePublished.connect(() => root.statePublished());
        item.workspaceChanged.connect(function () {
          root.workspaceChanged();
        });
        item.activeWindowChanged.connect(function () {
          root.activeWindowChanged();
        });
        item.windowListChanged.connect(function () {
          root.windowListChanged();
        });
        item.displayScalesChanged.connect(function () {
          root.displayScalesChanged();
        });
      } else
        NiriIpcStatus.reportUnavailable();
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        NiriIpcStatus.reportUnavailable();
      }
    }
  }

  function updateKeyboardLayouts(layouts) {
    if (available)
      loader.item.updateKeyboardLayouts(layouts);
  }

  function initialize() {
    if (available)
      loader.item.initialize();
  }

  function safeUpdateOutputs() {
    if (available)
      loader.item.safeUpdateOutputs();
  }

  function safeUpdateWorkspaces() {
    if (available)
      loader.item.safeUpdateWorkspaces();
  }

  function getWindowOutput(win) {
    return available ? loader.item.getWindowOutput(win) : null;
  }

  function toSortedWindowList(windowList) {
    return available ? loader.item.toSortedWindowList(windowList) : [];
  }

  function safeUpdateWindows() {
    if (available)
      loader.item.safeUpdateWindows();
  }

  function queryDisplayScales() {
    if (available)
      loader.item.queryDisplayScales();
  }

  function switchToWorkspace(workspace) {
    if (available)
      loader.item.switchToWorkspace(workspace);
  }

  function scrollWorkspaceContent(direction) {
    if (available)
      loader.item.scrollWorkspaceContent(direction);
  }

  function focusWindow(window) {
    if (available)
      loader.item.focusWindow(window);
  }

  function navigateEdge(output, edge, requestId, completed) {
    if (available)
      loader.item.navigateEdge(output, edge, requestId, completed);
    else
      completed({
                  requestId: requestId,
                  outcome: "unknown"
                });
  }

  function closeWindow(window) {
    if (available)
      loader.item.closeWindow(window);
  }

  function moveWindowToWorkspace(windowId, workspaceId, completed, insertAtIndex) {
    if (available)
      loader.item.moveWindowToWorkspace(windowId, workspaceId, completed, insertAtIndex);
    else if (typeof completed === "function")
      completed(false, "Niri IPC unavailable");
  }

  function moveWindowWithinWorkspace(windowId, target, completed) {
    if (available)
      loader.item.moveWindowWithinWorkspace(windowId, target, completed);
    else if (typeof completed === "function")
      completed(false, "Niri IPC unavailable", null);
  }

  function turnOffMonitors() {
    if (available)
      loader.item.turnOffMonitors();
  }

  function turnOnMonitors() {
    if (available)
      loader.item.turnOnMonitors();
  }

  function logout() {
    if (available)
      loader.item.logout();
  }

  function cycleKeyboardLayout() {
    if (available)
      loader.item.cycleKeyboardLayout();
  }

  function getFocusedScreen() {
    return available ? loader.item.getFocusedScreen() : null;
  }

  function spawn(command) {
    if (available)
      loader.item.spawn(command);
  }
}
