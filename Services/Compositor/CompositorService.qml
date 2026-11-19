pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Control
import qs.Services.Locker
import qs.Services.UI

Singleton {
  id: root

  // Compositor detection
  property bool isHyprland: false
  property bool isNiri: false
  property bool isSway: false
  property bool isMango: false
  property bool isLabwc: false
  property bool isExtWorkspace: false
  property bool isScroll: false

  readonly property var niriBackend: isNiri ? backend : null

  // Generic workspace and window data
  property ListModel workspaces: ListModel {}
  property ListModel windows: ListModel {}

  // Focused-window identity. Backends publish window records with a stable
  // per-window `id` and the compositor's `focusedWindowId` (null: none),
  // maintained from its own focus events. Every focus view below — the row's
  // isFocused, focusedWindowIndex, getFocusedWindow() — is derived from that
  // one id here, never kept as separate state that could disagree.
  //
  // Publication contract: a backend assigns a new `windows` array for every
  // list change and its `focusedWindowId` before emitting windowListChanged
  // or activeWindowChanged, in either order. On any of them the facade
  // reconciles the whole snapshot — rows, row flags, then one focus snapshot
  // the getters read — and only then notifies. A focus the window list does
  // not contain yet is published as none until the list catches up.
  readonly property int focusedWindowIndex: _focus.index
  // Declared after the index and bound to it as well: Qt notifies dependents
  // in connection order, so a changed index updates this id before any
  // consumer handler of either property runs; neither is ever seen stale.
  readonly property var focusedWindowId: focusIdAt(focusedWindowIndex)
  property var _focus: ({
                          "id": null,
                          "index": -1,
                          "window": null,
                          "title": ""
                        })
  property var _publishedWindows: null

  // Display scale data
  property var displayScales: ({})
  property bool displayScalesLoaded: false

  // Overview state (Niri-specific, defaults to false for other compositors)
  property bool overviewActive: false

  // Global workspaces flag (workspaces shared across all outputs)
  // True for LabWC (stacking compositor), false for tiling WMs with per-output workspaces
  property bool globalWorkspaces: false

  // Generic events
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged

  // Backend service loader
  property var backend: null

  // True inside the bundled locker process (its shell.qml sets the
  // marker): the lock-supervision machinery must never recurse — the
  // locker does not spawn lockers.
  property bool _isLockerProcess: Quickshell.env("ATMOSPHERA_LOCKSCREEN") === "1"

  Component.onCompleted: {
    // Load display scales from ShellState
    Qt.callLater(() => {
      if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
        loadDisplayScalesFromState();
      }
    });

    detectCompositor();

    if (!root._isLockerProcess)
      LockOwnerService.init();
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadDisplayScalesFromState();
      }
    }
  }

  function detectCompositor() {
    const hyprlandSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
    const niriSocket = Quickshell.env("NIRI_SOCKET");
    const swaySock = Quickshell.env("SWAYSOCK");
    const currentDesktop = Quickshell.env("XDG_CURRENT_DESKTOP");
    const labwcPid = Quickshell.env("LABWC_PID");

    // Check for MangoWC using XDG_CURRENT_DESKTOP environment variable
    // MangoWC sets XDG_CURRENT_DESKTOP=mango
    if (currentDesktop && currentDesktop.toLowerCase().includes("mango")) {
      isHyprland = false;
      isNiri = false;
      isSway = false;
      isMango = true;
      isLabwc = false;
      isExtWorkspace = false;
      backendLoader.sourceComponent = mangoComponent;
    } else if (labwcPid && labwcPid.length > 0) {
      isHyprland = false;
      isNiri = false;
      isSway = false;
      isMango = false;
      isLabwc = true;
      isExtWorkspace = false;
      backendLoader.sourceComponent = labwcComponent;
      Logger.i("CompositorService", "Detected LabWC with PID: " + labwcPid);
    } else if (niriSocket && niriSocket.length > 0) {
      isHyprland = false;
      isNiri = true;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isExtWorkspace = false;
      backendLoader.sourceComponent = niriComponent;
    } else if (hyprlandSignature && hyprlandSignature.length > 0) {
      isHyprland = true;
      isNiri = false;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isExtWorkspace = false;
      backendLoader.sourceComponent = hyprlandComponent;
    } else if (swaySock && swaySock.length > 0) {
      isHyprland = false;
      isNiri = false;
      isSway = true;
      isMango = false;
      isLabwc = false;
      isExtWorkspace = false;
      isScroll = currentDesktop && currentDesktop.toLowerCase().includes("scroll");
      backendLoader.sourceComponent = swayComponent;
    } else {
      // Always fallback to ext-workspace-v1
      isHyprland = false;
      isNiri = false;
      isSway = false;
      isMango = false;
      isLabwc = false;
      isExtWorkspace = true;
      backendLoader.sourceComponent = extWorkspaceComponent;
      Logger.i("CompositorService", "Using generic ext-workspace backend (no recognized compositor env)");
    }
  }

  Loader {
    id: backendLoader
    onLoaded: {
      if (item) {
        if (isScroll) {
          item.msgCommand = "scrollmsg";
        }
        root.backend = item;
        setupBackendConnections();
        backend.initialize();
      }
    }
  }

  // Load display scales from ShellState
  function loadDisplayScalesFromState() {
    try {
      const cached = ShellState.getDisplay();
      if (cached && Object.keys(cached).length > 0) {
        displayScales = cached;
        displayScalesLoaded = true;
        Logger.d("CompositorService", "Loaded display scales from ShellState");
      } else {
        // Migration is now handled in Settings.qml
        displayScalesLoaded = true;
      }
    } catch (error) {
      Logger.e("CompositorService", "Failed to load display scales:", error);
      displayScalesLoaded = true;
    }
  }

  // Hyprland backend component
  Component {
    id: hyprlandComponent
    HyprlandService {
      id: hyprlandBackend
    }
  }

  // Niri backend component
  Component {
    id: niriComponent
    NiriService {
      id: niriBackend
    }
  }

  // Sway backend component
  Component {
    id: swayComponent
    SwayService {
      id: swayBackend
    }
  }

  // Mango backend component
  Component {
    id: mangoComponent
    MangoService {
      id: mangoBackend
    }
  }

  // Labwc backend component
  Component {
    id: labwcComponent
    LabwcService {
      id: labwcBackend
    }
  }

  // Generic ext-workspace (WindowManager) when compositor env is unknown
  Component {
    id: extWorkspaceComponent
    ExtWorkspaceService {
      id: extWorkspaceBackend
    }
  }

  function setupBackendConnections() {
    if (!backend)
      return;

    // Connect backend signals to facade signals
    backend.workspaceChanged.connect(() => {
      // Sync workspaces when they change
      syncWorkspaces();
      // Forward the signal
      workspaceChanged();
    });

    // Either notification may arrive first; each reconciles the full snapshot.
    backend.activeWindowChanged.connect(() => reconcileWindows());
    backend.windowListChanged.connect(() => reconcileWindows());

    // Overview state (Niri-specific)
    if (backend.overviewActiveChanged) {
      backend.overviewActiveChanged.connect(() => {
        overviewActive = backend.overviewActive;
      });
    }

    // Initial sync
    syncWorkspaces();
    reconcileWindows();
    if (backend.overviewActive !== undefined) {
      overviewActive = backend.overviewActive;
    }
    if (backend.globalWorkspaces !== undefined) {
      globalWorkspaces = backend.globalWorkspaces;
    }
  }

  function syncWorkspaces() {
    workspaces.clear();
    const ws = backend.workspaces;
    for (var i = 0; i < ws.count; i++) {
      workspaces.append(ws.get(i));
    }
    // Emit signal to notify listeners that workspace list has been updated
    workspacesChanged();
  }

  function reconcileWindows() {
    if (!backend)
      return;
    const rows = backend.windows || [];
    const reported = backendFocusedWindowId();
    let index = -1;
    if (reported !== null) {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].id === reported) {
          index = i;
          break;
        }
      }
    }
    const id = index >= 0 ? reported : null;

    const listChanged = rows !== _publishedWindows;
    if (listChanged) {
      _publishedWindows = rows;
      windows.clear();
      if (rows.length > 0)
        windows.append(rows.map(row => Object.assign({}, row, {
                                                       "isFocused": row.id === id
                                                     })));
    } else {
      for (var j = 0; j < windows.count; j++) {
        const focused = j === index;
        if (windows.get(j).isFocused !== focused)
          windows.setProperty(j, "isFocused", focused);
      }
    }

    const window = index >= 0 ? Object.assign({}, rows[index], {
                                                "isFocused": true
                                              }) : null;
    const title = window && window.title !== undefined && window.title !== null ? String(window.title).replace(/(\r\n|\n|\r)/g, "") : "";
    const focusChanged = id !== _focus.id || index !== _focus.index || title !== _focus.title || (window ? window.appId : undefined) !== (_focus.window ? _focus.window.appId : undefined);
    if (listChanged || focusChanged) {
      _focus = {
        "id": id,
        "index": index,
        "window": window,
        "title": title
      };
    }

    // Notify only once every view above describes the same state.
    if (listChanged)
      windowListChanged();
    if (focusChanged)
      activeWindowChanged();
  }

  function focusIdAt(index) {
    return _focus.index === index ? _focus.id : null;
  }

  function backendFocusedWindowId() {
    const id = backend ? backend.focusedWindowId : null;
    return id === undefined || id === "" ? null : id;
  }

  // Update display scales from backend
  function updateDisplayScales() {
    if (!backend || !backend.queryDisplayScales) {
      Logger.w("CompositorService", "Backend does not support display scale queries");
      return;
    }

    backend.queryDisplayScales();
  }

  // Called by backend when display scales are ready
  function onDisplayScalesUpdated(scales) {
    displayScales = scales;
    saveDisplayScalesToCache();
    Logger.d("CompositorService", "Display scales updated");
  }

  // Save display scales to cache
  function saveDisplayScalesToCache() {
    try {
      ShellState.setDisplay(displayScales);
      Logger.d("CompositorService", "Saved display scales to ShellState");
    } catch (error) {
      Logger.e("CompositorService", "Failed to save display scales:", error);
    }
  }

  // Public function to get scale for a specific display
  function getDisplayScale(displayName) {
    if (!displayName || !displayScales[displayName]) {
      return 1.0;
    }
    return displayScales[displayName].scale || 1.0;
  }

  // Public function to get all display info for a specific display
  function getDisplayInfo(displayName) {
    if (!displayName || !displayScales[displayName]) {
      return null;
    }
    return displayScales[displayName];
  }

  // Focused window record from the published focus snapshot, or null
  function getFocusedWindow() {
    return _focus.window;
  }

  // Get focused screen from compositor
  function getFocusedScreen() {
    if (backend && backend.getFocusedScreen) {
      return backend.getFocusedScreen();
    }
    return null;
  }

  // Get focused window title
  function getFocusedWindowTitle() {
    return _focus.title;
  }

  // Get clean app name from appId
  // Extracts the last segment from reverse domain notation (e.g., "org.kde.dolphin" -> "Dolphin")
  // Falls back to title if appId is empty
  function getCleanAppName(appId, fallbackTitle) {
    var name = (appId || "").split(".").pop() || fallbackTitle || "Unknown";
    return name.charAt(0).toUpperCase() + name.slice(1);
  }

  function getWindowsForWorkspace(workspaceId) {
    var windowsInWs = [];
    for (var i = 0; i < windows.count; i++) {
      var window = windows.get(i);
      if (window.workspaceId === workspaceId) {
        // Snapshot to plain JS object so callers never hold live ListModel
        // proxies that become invalid when syncWindows() clears the model.
        windowsInWs.push({
                           id: window.id,
                           title: window.title,
                           appId: window.appId,
                           isFocused: window.isFocused,
                           workspaceId: window.workspaceId,
                           handle: window.handle
                         });
      }
    }
    return windowsInWs;
  }

  // Generic workspace switching
  function switchToWorkspace(workspace) {
    if (backend && backend.switchToWorkspace) {
      backend.switchToWorkspace(workspace);
    } else {
      Logger.w("Compositor", "No backend available for workspace switching");
    }
  }

  // Scrollable workspace content (Niri)
  function scrollWorkspaceContent(direction) {
    if (backend && backend.scrollWorkspaceContent) {
      backend.scrollWorkspaceContent(direction);
    }
  }

  // Get current workspace
  function getCurrentWorkspace() {
    for (var i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i);
      if (ws.isFocused) {
        return ws;
      }
    }
    return null;
  }

  // Get active workspaces
  function getActiveWorkspaces() {
    const activeWorkspaces = [];
    for (var i = 0; i < workspaces.count; i++) {
      const ws = workspaces.get(i);
      if (ws.isActive) {
        activeWorkspaces.push(ws);
      }
    }
    return activeWorkspaces;
  }

  // Set focused window
  function focusWindow(window) {
    if (backend && backend.focusWindow) {
      backend.focusWindow(window);
    } else {
      Logger.w("Compositor", "No backend available for window focus");
    }
  }

  // Close window
  function closeWindow(window) {
    if (backend && backend.closeWindow) {
      backend.closeWindow(window);
    } else {
      Logger.w("Compositor", "No backend available for window closing");
    }
  }

  // Spawn command
  function spawn(command) {
    // Ensure command is a proper JS array (QML lists can behave unexpectedly in some contexts)
    const cmdArray = Array.isArray(command) ? command : (command && typeof command === "object" && command.length !== undefined) ? Array.from(command) : [command];

    Logger.d("CompositorService", `Spawning: ${cmdArray.join(" ")}`);
    if (backend && backend.spawn) {
      backend.spawn(cmdArray);
    } else {
      try {
        Quickshell.execDetached(cmdArray);
      } catch (e) {
        Logger.e("CompositorService", "Failed to execute detached:", e);
      }
    }
  }

  // Session management helper for custom commands
  function getCustomCommand(action) {
    const powerOptions = Settings.data.sessionMenu.powerOptions || [];
    for (let i = 0; i < powerOptions.length; i++) {
      const option = powerOptions[i];
      if (option.action === action && option.enabled && option.command && option.command.trim() !== "") {
        return option.command.trim();
      }
    }
    return "";
  }

  function executeSessionAction(action, defaultCommand) {
    if (action === "lock") {
      LockOwnerService.requestLock("session-action", false);
      return true;
    }
    const customCommand = getCustomCommand(action);
    if (customCommand) {
      Logger.i("Compositor", `Executing custom command for action: ${action} Command: ${customCommand}`);
      Quickshell.execDetached(["sh", "-c", customCommand]);
      return true;
    }
    return false;
  }

  // Session management
  function logout() {
    Logger.i("Compositor", "Logout requested");
    if (executeSessionAction("logout"))
      return;

    if (backend && backend.logout) {
      backend.logout();
    } else {
      Logger.w("Compositor", "No backend available for logout");
    }
  }

  function shutdown() {
    Logger.i("Compositor", "Shutdown requested");
    HooksService.runHandler("shutdownAction", () => {
      if (executeSessionAction("shutdown"))
        return;
      HooksService.executeSessionHook("shutdown", () => {
        Quickshell.execDetached(["sh", "-c", "systemctl poweroff || loginctl poweroff"]);
      });
    });
  }

  function reboot() {
    Logger.i("Compositor", "Reboot requested");
    HooksService.runHandler("rebootAction", () => {
      if (executeSessionAction("reboot"))
        return;
      HooksService.executeSessionHook("reboot", () => {
        Quickshell.execDetached(["sh", "-c", "systemctl reboot || loginctl reboot"]);
      });
    });
  }

  function userspaceReboot() {
    Logger.i("Compositor", "Userspace reboot requested");
    HooksService.runHandler("userspaceRebootAction", () => {
      if (executeSessionAction("userspaceReboot"))
        return;
      HooksService.executeSessionHook("userspaceReboot", () => {
        Quickshell.execDetached(["sh", "-c", "systemctl soft-reboot"]);
      });
    });
  }

  function rebootToUefi() {
    Logger.i("Compositor", "Reboot to UEFI firmware requested");
    HooksService.runHandler("rebootToUefiAction", () => {
      if (executeSessionAction("rebootToUefi"))
        return;
      HooksService.executeSessionHook("rebootToUefi", () => {
        Quickshell.execDetached(["sh", "-c", "systemctl reboot --firmware-setup || loginctl reboot --firmware-setup"]);
      });
    });
  }

  function turnOffMonitors() {
    Logger.i("Compositor", "Turn off monitors requested");
    HooksService.runHandler("screenOffAction", () => {
      if (backend && backend.turnOffMonitors) {
        backend.turnOffMonitors();
      } else {
        Logger.w("Compositor", "No backend available for turnOffMonitors");
      }
    });
  }

  function turnOnMonitors() {
    Logger.i("Compositor", "Turn on monitors requested");
    if (backend && backend.turnOnMonitors) {
      backend.turnOnMonitors();
    } else {
      Logger.w("Compositor", "No backend available for turnOnMonitors");
    }
  }

  function suspend() {
    Logger.i("Compositor", "Suspend requested");
    HooksService.runHandler("suspendAction", () => {
      if (executeSessionAction("suspend"))
        return;
      Quickshell.execDetached(["sh", "-c", "systemctl suspend || loginctl suspend"]);
    });
  }

  function lock() {
    LockOwnerService.requestLock("compositor", false);
  }

  function hibernate() {
    Logger.i("Compositor", "Hibernate requested");
    HooksService.runHandler("hibernateAction", () => {
      if (executeSessionAction("hibernate"))
        return;
      Quickshell.execDetached(["sh", "-c", "systemctl hibernate || loginctl hibernate"]);
    });
  }

  function cycleKeyboardLayout() {
    if (backend && backend.cycleKeyboardLayout) {
      backend.cycleKeyboardLayout();
    }
  }

  function lockAndSuspend() {
    if (root._isLockerProcess)
      return;
    if (!Settings.data.general.lockScreenEnabled) {
      Logger.i("Compositor", "Lock and suspend requested but lockScreenEnabled is false — suspending without lock");
      suspend();
      return;
    }
    LockOwnerService.requestLock("lock-and-suspend", true);
  }

  Connections {
    target: LockOwnerService
    function onSuspendReady() { root.suspend(); }
  }

}
