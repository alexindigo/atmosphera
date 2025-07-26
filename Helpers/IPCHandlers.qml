import Quickshell.Io
import Quickshell.Wayland

IpcHandler {
    property var appLauncherPanel
    property var lockScreen

    target: "globalIPC"

    // Toggle Fullscreen
    function toggleFullscreen(): void {
        console.log("[IPC] toggleFullscreen() called")
        if (ToplevelManager.activeToplevel) {
            if (ToplevelManager.activeToplevel.fullscreen) {
                // Exit fullscreen
                ToplevelManager.activeToplevel.fullscreen = false;
            } else {
                // Enter fullscreen
                ToplevelManager.activeToplevel.fullscreen = true;
            }
        } else {
            console.warn("[IPC] No active toplevel window to toggle fullscreen");
        }
    }

    // Toggle Applauncher visibility
    function toggleLauncher(): void {
        if (!appLauncherPanel) {
            console.warn("AppLauncherIpcHandler: appLauncherPanel not set!");
            return;
        }
        if (appLauncherPanel.visible) {
            appLauncherPanel.hidePanel();
        } else {
            console.log("[IPC] Applauncher show() called");
            appLauncherPanel.showAt();
        }
    }

    // Toggle LockScreen
    function toggleLock(): void {
        if (!lockScreen) {
            console.warn("LockScreenIpcHandler: lockScreen not set!");
            return;
        }
        console.log("[IPC] LockScreen show() called");
        lockScreen.locked = true;
    }
}
