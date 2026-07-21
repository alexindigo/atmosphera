pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Power
import qs.Services.Theming
import qs.Services.UI

Singleton {
  id: root

  // Hook connections for automatic script execution
  Connections {
    target: Settings.data.colorSchemes
    function onDarkModeChanged() {
      executeDarkModeHook(Settings.data.colorSchemes.darkMode);
    }
  }

  // Pending wallpaper hook when waiting for color generation
  property var pendingWallpaperHook: null

  Connections {
    target: WallpaperService
    function onWallpaperChanged(screenName, path) {
      // Check if we need to wait for color generation
      if (Settings.data.colorSchemes.useWallpaperColors) {
        var effectiveMonitor = Settings.data.colorSchemes.monitorForColors;
        if (effectiveMonitor === "" || effectiveMonitor === undefined) {
          effectiveMonitor = Screen.name;
        }

        if (screenName === effectiveMonitor) {
          // Store pending hook and wait for colors to be generated
          root.pendingWallpaperHook = {
            path: path,
            screenName: screenName
          };
          return;
        }
      }
      // No color generation, execute immediately
      executeWallpaperHook(path, screenName);
    }
  }

  Connections {
    target: TemplateProcessor
    function onColorsGenerated() {
      // Execute pending wallpaper hook after colors are ready
      if (root.pendingWallpaperHook) {
        const hook = root.pendingWallpaperHook;
        root.pendingWallpaperHook = null;
        executeWallpaperHook(hook.path, hook.screenName);
      }
      executeColorGenerationHook();
    }
  }

  // Track lock screen state for unlock hook
  property bool wasLocked: false

  Connections {
    target: PanelService
    function onLockScreenChanged() {
      if (PanelService.lockScreen) {
        lockScreenActiveConnection.target = PanelService.lockScreen;
      }
    }
  }

  Connections {
    id: lockScreenActiveConnection
    target: PanelService.lockScreen
    function onActiveChanged() {
      // Detect lock: was unlocked, now locked
      if (!wasLocked && PanelService.lockScreen.active) {
        executeLockHook();
      }
      // Detect unlock: was locked, now not locked
      if (wasLocked && !PanelService.lockScreen.active) {
        executeUnlockHook();
      }
      wasLocked = PanelService.lockScreen.active;
    }
  }

  // Track performance mode state for hooks
  property bool wasPerformanceModeEnabled: false

  Connections {
    target: PowerProfileService
    function onAtmospheraPerformanceModeChanged() {
      const isEnabled = PowerProfileService.atmospheraPerformanceMode;

      // Detect enabled: was disabled, now enabled
      if (!wasPerformanceModeEnabled && isEnabled) {
        executePerformanceModeEnabledHook();
      }
      // Detect disabled: was enabled, now disabled
      if (wasPerformanceModeEnabled && !isEnabled) {
        executePerformanceModeDisabledHook();
      }
      wasPerformanceModeEnabled = isEnabled;
    }
  }

  // Execute wallpaper change hook
  function executeWallpaperHook(wallpaperPath, screenName) {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.wallpaperChange;
    if (!script || script === "") {
      return;
    }

    try {
      const theme = Settings.data.colorSchemes.darkMode ? "dark" : "light";
      let command = script.replace(/\$1/g, wallpaperPath);
      command = command.replace(/\$2/g, screenName || "");
      command = command.replace(/\$3/g, theme);
      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.d("HooksService", `Executed wallpaper hook: ${command}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute wallpaper hook: ${e}`);
    }
  }

  // Execute dark mode change hook
  function executeDarkModeHook(isDarkMode) {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.darkModeChange;
    if (!script || script === "") {
      return;
    }

    try {
      const command = script.replace(/\$1/g, isDarkMode ? "true" : "false");
      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.d("HooksService", `Executed dark mode hook: ${command}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute dark mode hook: ${e}`);
    }
  }

  // Execute screen lock hook
  function executeLockHook() {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.screenLock;
    if (!script || script === "") {
      return;
    }

    try {
      // Pass "lock" as $1 via shell arguments so the script receives it
      Quickshell.execDetached(["sh", "-lc", script, "lock-hook", "lock"]);
      Logger.d("HooksService", `Executed screen lock hook: ${script}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute screen lock hook: ${e}`);
    }
  }

  // Execute screen unlock hook
  function executeUnlockHook() {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.screenUnlock;
    if (!script || script === "") {
      return;
    }

    try {
      // Pass "unlock" as $1 via shell arguments so the script receives it
      Quickshell.execDetached(["sh", "-lc", script, "unlock-hook", "unlock"]);
      Logger.d("HooksService", `Executed screen unlock hook: ${script}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute screen unlock hook: ${e}`);
    }
  }

  // Execute performance mode enabled hook
  function executePerformanceModeEnabledHook() {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.performanceModeEnabled;
    if (!script || script === "") {
      return;
    }

    try {
      Quickshell.execDetached(["sh", "-lc", script]);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute performance mode enabled hook: ${e}`);
    }
  }

  // Execute performance mode disabled hook
  function executePerformanceModeDisabledHook() {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.performanceModeDisabled;
    if (!script || script === "") {
      return;
    }

    try {
      Quickshell.execDetached(["sh", "-lc", script]);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute performance mode disabled hook: ${e}`);
    }
  }

  // Execute color generation hook
  function executeColorGenerationHook() {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.colorGeneration;
    if (!script || script === "") {
      return;
    }

    try {
      const theme = Settings.data.colorSchemes.darkMode ? "dark" : "light";
      const command = script.replace(/\$1/g, theme);
      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.d("HooksService", `Executed color generation hook: ${command}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute color generation hook: ${e}`);
    }
  }

  // Desktop click hooks — $1=screenName, $2=x, $3=y
  function executeDesktopLeftClickHook(screenName, x, y) {
    if (!Settings.data.hooks?.enabled)
      return;
    const script = Settings.data.hooks?.desktopLeftClick;
    if (!script || script === "")
      return;
    try {
      const command = script.replace(/\$1/g, screenName).replace(/\$2/g, String(x)).replace(/\$3/g, String(y));
      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.d("HooksService", `Executed desktop left click hook: ${command}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute desktop left click hook: ${e}`);
    }
  }

  function executeDesktopRightClickHook(screenName, x, y) {
    if (!Settings.data.hooks?.enabled)
      return;
    const script = Settings.data.hooks?.desktopRightClick;
    if (!script || script === "")
      return;
    try {
      const command = script.replace(/\$1/g, screenName).replace(/\$2/g, String(x)).replace(/\$3/g, String(y));
      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.d("HooksService", `Executed desktop right click hook: ${command}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute desktop right click hook: ${e}`);
    }
  }

  function executeDesktopMiddleClickHook(screenName, x, y) {
    if (!Settings.data.hooks?.enabled)
      return;
    const script = Settings.data.hooks?.desktopMiddleClick;
    if (!script || script === "")
      return;
    try {
      const command = script.replace(/\$1/g, screenName).replace(/\$2/g, String(x)).replace(/\$3/g, String(y));
      Quickshell.execDetached(["sh", "-lc", command]);
      Logger.d("HooksService", `Executed desktop middle click hook: ${command}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute desktop middle click hook: ${e}`);
    }
  }

  // ─── Handler infrastructure ───

  readonly property int handlerTimeoutMs: 5000

  property var pendingHandlerCallback: null
  property bool handlerWasExclusive: false

  Timer {
    id: handlerTimeoutTimer
    interval: root.handlerTimeoutMs
    repeat: false
    onTriggered: {
      Logger.w("HooksService", `Handler timed out after ${root.handlerTimeoutMs}ms, proceeding with fallback`);
      if (handlerProcess.running) {
        handlerProcess.running = false;
      }
      root._completeHandler(true);
    }
  }

  Process {
    id: handlerProcess
    onExited: (exitCode, exitStatus) => {
      handlerTimeoutTimer.stop();
      if (exitCode !== 0) {
        Logger.w("HooksService", `Handler exited with code ${exitCode}`);
      }
      root._completeHandler(!root.handlerWasExclusive || exitCode === 0);
    }
  }

  function _completeHandler(runBuiltin) {
    const callback = root.pendingHandlerCallback;
    root.pendingHandlerCallback = null;
    if (runBuiltin && callback) {
      callback();
    }
  }

  function handlerFor(name) {
    if (!Settings.data.hooks?.enabled) {
      return null;
    }
    try {
      const h = Settings.data.hooks?.handlers?.[name];
      if (h && h.command && h.command !== "") {
        return {
          command: h.command,
          exclusive: h.exclusive === true
        };
      }
    } catch (e) {
      // Schema not yet initialized — handler not configured
    }
    return null;
  }

  function runHandler(name, builtinCallback) {
    const handler = handlerFor(name);
    if (!handler) {
      if (builtinCallback) builtinCallback();
      return;
    }

    Logger.i("HooksService", `Running handler '${name}': ${handler.command}` + (handler.exclusive ? " (exclusive)" : ""));
    root.pendingHandlerCallback = builtinCallback || null;
    root.handlerWasExclusive = handler.exclusive;
    handlerTimeoutTimer.restart();
    handlerProcess.command = ["sh", "-lc", handler.command];
    handlerProcess.running = true;
  }

  // ─── Legacy blocking power hook (deprecated) ───

  property var pendingPowerCallback: null

  Process {
    id: powerHookProcess
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) {
        Logger.w("HooksService", `Power hook failed with exit code ${exitCode}`);
      }

      if (pendingPowerCallback !== null) {
        const callback = pendingPowerCallback;
        pendingPowerCallback = null;
        callback();
      }
    }
  }

  function runPowerHook(script, callback) {
    pendingPowerCallback = callback;
    powerHookProcess.command = ["sh", "-lc", script];
    powerHookProcess.running = true;
  }

  function executeSessionHook(action, callback) {
    if (!Settings.data.hooks?.enabled) {
      callback();

      return;
    }

    const script = Settings.data.hooks?.session;
    if (!script) {
      callback();

      return;
    }

    Logger.i("HooksService", `Executing session hook for ${action}`);
    runPowerHook(`${script} ${action}`, callback);
  }

  // Execute startup hook
  function executeStartupHook() {
    if (!Settings.data.hooks?.enabled) {
      return;
    }

    const script = Settings.data.hooks?.startup;
    if (!script || script === "") {
      return;
    }

    try {
      Quickshell.execDetached(["sh", "-lc", script]);
      Logger.d("HooksService", `Executed startup hook: ${script}`);
    } catch (e) {
      Logger.e("HooksService", `Failed to execute startup hook: ${e}`);
    }
  }

  // Initialize the service
  function init() {
    Logger.i("HooksService", "Service started");
    // Initialize lock screen state tracking
    Qt.callLater(() => {
      if (PanelService.lockScreen) {
        wasLocked = PanelService.lockScreen.active;
        lockScreenActiveConnection.target = PanelService.lockScreen;
      }
      // Initialize performance mode state tracking
      wasPerformanceModeEnabled = PowerProfileService.atmospheraPerformanceMode;
      // Execute startup hook
      executeStartupHook();
    });
  }
}
