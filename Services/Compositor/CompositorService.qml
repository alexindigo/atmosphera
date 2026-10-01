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
  property int focusedWindowIndex: -1

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

    // Boot recovery: session still locked at shell start with no live
    // locker → spawn the configured locker for its A.1.3 re-engage.
    // Delayed so LockerService's LockedHint + name watches converge.
    if (!root._isLockerProcess)
      Qt.callLater(() => bootRecoveryTimer.start());
  }

  Timer {
    id: bootRecoveryTimer
    interval: 2000
    repeat: false
    onTriggered: root._bootRecover()
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

    backend.activeWindowChanged.connect(() => {
      // Only sync focus state, not entire window list
      syncFocusedWindow();
      // Forward the signal
      activeWindowChanged();
    });

    backend.windowListChanged.connect(() => {
      syncWindows();
    });

    // Property bindings - use automatic property change signal
    backend.focusedWindowIndexChanged.connect(() => {
      focusedWindowIndex = backend.focusedWindowIndex;
    });

    // Overview state (Niri-specific)
    if (backend.overviewActiveChanged) {
      backend.overviewActiveChanged.connect(() => {
        overviewActive = backend.overviewActive;
      });
    }

    // Initial sync
    syncWorkspaces();
    syncWindows();
    focusedWindowIndex = backend.focusedWindowIndex;
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

  function syncWindows() {
    windows.clear();
    const ws = backend.windows;
    for (var i = 0; i < ws.length; i++) {
      windows.append(ws[i]);
    }
    // Emit signal to notify listeners that window list has been updated
    windowListChanged();
  }

  // Sync only the focused window state, not the entire window list
  function syncFocusedWindow() {
    const newIndex = backend.focusedWindowIndex;

    // Update isFocused flags by syncing from backend
    for (var i = 0; i < windows.count && i < backend.windows.length; i++) {
      const backendFocused = backend.windows[i].isFocused;
      if (windows.get(i).isFocused !== backendFocused) {
        windows.setProperty(i, "isFocused", backendFocused);
      }
    }

    focusedWindowIndex = newIndex;
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

  // Get focused window
  function getFocusedWindow() {
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.count) {
      return windows.get(focusedWindowIndex);
    }
    return null;
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
    if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.count) {
      var title = windows.get(focusedWindowIndex).title;
      if (title !== undefined) {
        title = title.replace(/(\r\n|\n|\r)/g, "");
      }
      return title || "";
    }
    return "";
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

  function _spawnExternalLocker() {
    var cmd = Settings.data.general.externalLockCommand;
    if (cmd !== "") {
      HooksService.executeLockHook();
      Logger.i("Compositor", "Launching external locker:", cmd);
      externalLockerProcess.command = ["sh", "-c", cmd];
      externalLockerProcess.running = true;
      return true;
    }
    Logger.w("Compositor", "External lock mode enabled but no command configured");
    return false;
  }

  // --- Out-of-process lock actuation (no-modes model) ---
  // The lock screen is ALWAYS a separate process: class 3 — a
  // persistent contract service owning app.atmosphera.Locker (signal
  // Lock()); class 2 — externalLockCommand spawned per lock; class 1 —
  // the bundled locker config (default) spawned per lock. Spawned
  // lockers self-engage and exit after unlock; engagement and lock
  // state are observed via LockedHint (LockerService.locked). The
  // in-process lock screen survives only as the spawn-failure fallback.
  property bool _lockerSpawnPending: false
  property int _lockerRespawnAttempts: 0
  property int _lockerLivenessFails: 0
  property bool _lockerRespawnInFlight: false
  property string _spawnedLockerCmd: ""

  function _bundledLockerCommand() {
    return "qs -c atmosphera-lockscreen";
  }

  // The command a spawned (class 1–2) locker would be running under —
  // the liveness pattern for respawn and boot-recovery probes. Leading
  // VAR=value env assignments don't appear in the spawned process's
  // cmdline, so the pgrep pattern strips them.
  function _spawnedLockerCommand() {
    var cmd = Settings.data.general.externalLockCommand;
    return cmd !== "" ? cmd : root._bundledLockerCommand();
  }

  function _lockerLivenessPattern(cmd) {
    var tokens = cmd.split(/\s+/);
    var i = 0;
    while (i < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i]))
      i++;
    return tokens.slice(i).join(" ").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  // Spawn the locker so it survives the shell: detached AND outside the
  // shell's cgroup — a systemd unit teardown of the shell (restart,
  // crash-reap) kills plain detached children of the unit. On systemd
  // the locker runs as its own transient user service; elsewhere plain
  // detached spawn has no cgroup reaper to escape.
  function _spawnLockerDetached(cmd) {
    var quoted = "'" + cmd.replace(/'/g, "'\\''") + "'";
    var probe = "if [ -S \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/systemd/private\" ] && command -v systemd-run >/dev/null 2>&1; then " + "exec systemd-run --user --collect --quiet -- sh -c " + quoted + "; " + "else exec sh -c " + quoted + "; fi";
    Quickshell.execDetached(["sh", "-c", probe]);
  }

  // Route a lock request out-of-process. Class 3 present → signal
  // (never spawn). Otherwise spawn the configured per-lock locker;
  // engagement is confirmed by LockedHint within 3 s or the in-process
  // fallback engages once (B.6). Callers guard on LockerService.locked.
  function _engageOutOfProcessLocker() {
    if (LockerService.contractAvailable) {
      LockerService.lock();
      return;
    }
    if (root._lockerSpawnPending)
      return; // spawn already in flight
    var cmd = root._spawnedLockerCommand();
    Logger.i("Compositor", "Spawning locker:", cmd);
    root._lockerSpawnPending = true;
    root._spawnedLockerCmd = cmd;
    root._lockerLivenessFails = 0; // spawn windows don't count as deaths
    lockerSpawnTimer.restart();
    root._spawnLockerDetached(cmd);
  }

  Connections {
    target: LockerService
    function onLockedChanged() {
      if (LockerService.locked) {
        root._lockerSpawnPending = false;
        lockerSpawnTimer.stop();
        root._lockerRespawnAttempts = 0;
        root._lockerLivenessFails = 0;
        root._armLivenessWatch();
      } else {
        root._lockerRespawnAttempts = 0; // clean unlock — healthy cycle
        lockerLivenessTimer.stop();
      }
    }
    // LockedHint convergence can land after the 2 s startup probe —
    // retry boot recovery once the watch is live (idempotent).
    function onLockedHintAvailableChanged() {
      if (LockerService.lockedHintAvailable)
        root._bootRecover();
    }
  }

  // Invisible degraded path (B.6) — the only surviving use of the
  // in-process lock screen.
  function _engageInProcessFallback(reason) {
    Logger.w("Compositor", reason + " — falling back to in-process lock screen");
    if (!lockAndSuspendTimer.running && PanelService && PanelService.lockScreen && !PanelService.lockScreen.active)
      PanelService.lockScreen.active = true;
  }

  // Spawned locker never engaged within 3 s -> in-process fallback (B.6).
  Timer {
    id: lockerSpawnTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (!root._lockerSpawnPending)
        return;
      if (LockerService.locked) {
        // LockedHint was already set (boot recovery / respawn of a dead
        // locker's session): re-engagement produces NO LockedHint
        // transition, so process liveness is the confirmation here.
        spawnLivenessProbe.running = true;
        return;
      }
      root._lockerSpawnPending = false;
      root._engageInProcessFallback("Spawned locker did not engage within 3 s");
    }
  }

  Process {
    id: spawnLivenessProbe
    command: ["pgrep", "-f", root._lockerLivenessPattern(root._spawnedLockerCmd)]
    onExited: function (exitCode) {
      if (!root._lockerSpawnPending)
        return;
      root._lockerSpawnPending = false;
      if (exitCode === 0) {
        root._armLivenessWatch(); // alive + LockedHint=yes → engaged
        return;
      }
      root._engageInProcessFallback("Spawned locker never appeared");
    }
  }

  // Spawned-locker liveness: while locked, probe for the process we
  // (would) spawn; two consecutive misses (6 s) = died while locked →
  // bounded respawn (B.6). Class 3 is supervised by its own deployment.
  function _armLivenessWatch() {
    if (root._isLockerProcess || LockerService.contractAvailable)
      return;
    if (root._spawnedLockerCmd === "")
      root._spawnedLockerCmd = root._spawnedLockerCommand();
    root._lockerLivenessFails = 0;
    lockerLivenessTimer.start();
  }

  Timer {
    id: lockerLivenessTimer
    interval: 3000
    repeat: true
    onTriggered: {
      if (!LockerService.locked || LockerService.contractAvailable || root._lockerSpawnPending) {
        stop();
        return;
      }
      lockerLivenessProbe.running = true;
    }
  }

  Process {
    id: lockerLivenessProbe
    command: ["pgrep", "-f", root._lockerLivenessPattern(root._spawnedLockerCmd)]
    onExited: function (exitCode) {
      if (!LockerService.locked || LockerService.contractAvailable || root._lockerSpawnPending) {
        root._lockerLivenessFails = 0;
        return;
      }
      if (exitCode === 0) {
        root._lockerLivenessFails = 0;
        return;
      }
      root._lockerLivenessFails++;
      if (root._lockerLivenessFails >= 2)
        root._respawnSpawnedLocker();
    }
  }

  function _respawnSpawnedLocker() {
    if (root._lockerRespawnInFlight)
      return; // concurrent probes must not double-spawn
    if (root._lockerRespawnAttempts >= 3) {
      Logger.e("Compositor", "Spawned locker died while locked and respawn attempts are exhausted — the compositor locked-session background stays until a locker returns");
      lockerLivenessTimer.stop();
      return;
    }
    root._lockerRespawnAttempts++;
    root._lockerLivenessFails = 0;
    root._lockerRespawnInFlight = true;
    Logger.w("Compositor", "Spawned locker died while locked — respawning (attempt " + root._lockerRespawnAttempts + "/3)");
    root._spawnLockerDetached(root._spawnedLockerCmd);
    respawnGraceTimer.restart();
  }

  // Grace covers the respawned process's boot+engage; probes during it
  // cannot count misses.
  Timer {
    id: respawnGraceTimer
    interval: 5000
    repeat: false
    onTriggered: {
      root._lockerRespawnInFlight = false;
      root._lockerLivenessFails = 0;
    }
  }

  // Boot recovery: shell start while the session is still locked and no
  // locker is alive (both died mid-lock) → spawn the configured locker;
  // it re-engages per A.1.3. A live class-3 service (name watch) or a
  // surviving spawned locker (liveness probe) makes this a no-op.
  // Runs at startup and again when the LockedHint watch converges, and
  // serves as the manual-recovery path for lock() while locked.
  function _bootRecover() {
    if (!LockerService.lockedHintAvailable || !LockerService.locked || LockerService.contractAvailable)
      return;
    if (root._spawnedLockerCmd === "")
      root._spawnedLockerCmd = root._spawnedLockerCommand();
    bootLivenessProbe.running = true;
  }

  Process {
    id: bootLivenessProbe
    command: ["pgrep", "-f", root._lockerLivenessPattern(root._spawnedLockerCmd)]
    onExited: function (exitCode) {
      if (!LockerService.locked || LockerService.contractAvailable)
        return;
      if (exitCode === 0) {
        root._armLivenessWatch(); // surviving locker around a shell restart
        return;
      }
      Logger.w("Compositor", "Session still locked at shell startup (LockedHint=yes) with no live locker — spawning for re-engagement");
      root._engageOutOfProcessLocker();
    }
  }

  function lock() {
    if (root._isLockerProcess)
      return;
    if (!Settings.data.general.lockScreenEnabled) {
      Logger.i("Compositor", "Lock requested but lockScreenEnabled is false — skipping");
      return;
    }
    Logger.i("Compositor", "LockScreen requested");
    HooksService.runHandler("lockAction", () => {
      if (executeSessionAction("lock"))
        return;
      if (Settings.data.general.lockScreenPlugin === "external" && _spawnExternalLocker())
        return; // legacy swaylock-mode
      if (LockerService.locked) {
        // Manual-recovery path: locked with no live locker (dead client,
        // compositor background) → spawn for the takeover.
        if (!LockerService.contractAvailable)
          root._bootRecover();
        return; // a live locker makes lock() idempotent
      }
      root._engageOutOfProcessLocker();
    });
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

  property int lockAndSuspendCheckCount: 0

  function lockAndSuspend() {
    if (root._isLockerProcess)
      return;
    if (!Settings.data.general.lockScreenEnabled) {
      Logger.i("Compositor", "Lock and suspend requested but lockScreenEnabled is false — suspending without lock");
      suspend();
      return;
    }
    Logger.i("Compositor", "Lock and suspend requested");

    // if a custom lock command exists, execute it and suspend without wait
    if (executeSessionAction("lock")) {
      suspend();
      return;
    }

    // Legacy swaylock-mode: spawn locker, then suspend immediately
    if (Settings.data.general.lockScreenPlugin === "external" && _spawnExternalLocker()) {
      suspend();
      return;
    }

    // Already locked (any class) → suspend immediately
    if (LockerService.locked || (PanelService && PanelService.lockScreen && PanelService.lockScreen.active)) {
      Logger.i("Compositor", "Screen already locked, suspending");
      suspend();
      return;
    }

    // Out-of-process engage (contract signal or per-lock spawn), then
    // wait for LockedHint before suspending (timer, 3 s timeout
    // suspends anyway).
    HooksService.runHandler("lockAction", () => {
      root._engageOutOfProcessLocker();
    });
    lockAndSuspendCheckCount = 0;
    lockAndSuspendTimer.start();
  }

  Timer {
    id: lockAndSuspendTimer
    interval: 100
    repeat: true
    running: false

    onTriggered: {
      lockAndSuspendCheckCount++;

      // LockedHint is the engagement confirmation for every class
      if (LockerService.locked) {
        Logger.i("Compositor", "Locker confirmed active, suspending");
        stop();
        lockAndSuspendCheckCount = 0;
        suspend();
        return;
      }

      if (lockAndSuspendCheckCount > 30) {
        // Max 3 seconds wait
        Logger.w("Compositor", "Locker failed to activate, suspending anyway");
        stop();
        lockAndSuspendCheckCount = 0;
        suspend();
        return;
      }

      // Check if lock screen is now active
      if (PanelService && PanelService.lockScreen && PanelService.lockScreen.active) {
        // Verify the lock screen component is loaded
        if (PanelService.lockScreen.item) {
          Logger.i("Compositor", "Lock screen confirmed active, suspending");
          stop();
          lockAndSuspendCheckCount = 0;
          suspend();
        } else {
          // Lock screen is active but component not loaded yet, wait a bit more
          if (lockAndSuspendCheckCount > 20) {
            // Max 2 seconds wait
            Logger.w("Compositor", "Lock screen active but component not loaded, suspending anyway");
            stop();
            lockAndSuspendCheckCount = 0;
            suspend();
          }
        }
      } else {
        // Lock screen not active yet, keep checking
        if (lockAndSuspendCheckCount > 30) {
          // Max 3 seconds wait
          Logger.w("Compositor", "Lock screen failed to activate, suspending anyway");
          stop();
          lockAndSuspendCheckCount = 0;
          suspend();
        }
      }
    }
  }

  Process {
    id: externalLockerProcess
    running: false
    command: []

    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("Compositor", "External locker failed, exit code:", exitCode, "\nstderr:", stderr.text);
        ToastService.showError(I18n.tr("toast.external-locker-failed"), I18n.tr("toast.external-locker-failed-description", {
                                                                                  "code": exitCode
                                                                                }), 5000);
      }
    }
  }
}
