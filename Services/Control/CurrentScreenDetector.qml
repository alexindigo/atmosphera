import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland as Hyprland
import Quickshell.I3 as I3
import qs.Commons
import qs.Services.Compositor

/**
* Detects which screen the cursor is currently on by creating a temporary
* invisible PanelWindow. Use withCurrentScreen() to get the screen asynchronously.
*
* Usage:
*   CurrentScreenDetector {
*     id: screenDetector
*   }
*
*   function doSomething() {
*     screenDetector.withCurrentScreen(function(screen) {
*       // screen is the ShellScreen where cursor is
*     })
*   }
*/
Item {
  id: root

  // Pending callback to execute once screen is detected
  property var pendingCallback: null

  // Detected screen
  property var detectedScreen: null

  // Signal emitted when screen is detected from the PanelWindow
  signal screenDetected(var detectedScreen)

  onScreenDetected: function (detectedScreen) {
    root.detectedScreen = detectedScreen;
    screenDetectorDebounce.restart();
  }

  /**
  * Execute callback with the screen where the cursor currently is.
  * On single-monitor setups, executes immediately.
  * On multi-monitor setups, briefly opens an invisible window to detect the screen.
  */
  function withCurrentScreen(callback: var): void {
    if (root.pendingCallback) {
      Logger.w("CurrentScreenDetector", "Another detection is pending, ignoring new call");
      return;
    }

    // Single monitor setup can execute immediately
    if (Quickshell.screens.length === 1) {
      callback(Quickshell.screens[0]);
      return;
    }

    // Try compositor-specific focused monitor detection first
    let screen = getCompositorFocusedScreen();

    if (screen) {
      // Apply the bar check if configured
      if (!Settings.data.general.allowPanelsOnScreenWithoutBar) {
        const monitors = Settings.data.bar.monitors || [];
        const hasBar = monitors.length === 0 || monitors.includes(screen.name);
        if (!hasBar) {
          screen = Quickshell.screens[0];
        }
      }
      Logger.d("CurrentScreenDetector", "Using compositor-detected screen:", screen.name);
      callback(screen);
      return;
    }

    // Fallback: Multi-monitor setup needs async detection via invisible PanelWindow
    root.detectedScreen = null;
    root.pendingCallback = callback;
    screenDetectorLoader.active = true;
  }

  /**
  * Helper function to get focused screen from compositor.
  * Returns the ShellScreen where the focused window is, or null if unavailable.
  */
  function getCompositorFocusedScreen(): var {
    let monitorName = null;

    // Hyprland: use Hyprland.focusedMonitor
    if (CompositorService.isHyprland) {
      const hyprMon = Hyprland.Hyprland.focusedMonitor;
      if (hyprMon) {
        monitorName = hyprMon.name;
        Logger.d("CurrentScreenDetector", "Hyprland focused monitor:", monitorName);
      }
    }
    // Sway/i3: use I3.focusedMonitor
    else if (CompositorService.isSway) {
      const i3Mon = I3.I3.focusedMonitor;
      if (i3Mon) {
        monitorName = i3Mon.name;
        Logger.d("CurrentScreenDetector", "Sway focused monitor:", monitorName);
      }
    }
    // Niri, Labwc and other wlroots compositors: infer from active toplevel window
    // (Niri supports wlr-foreign-toplevel-management since v0.1.1)
    else if (CompositorService.isNiri || CompositorService.isLabwc || CompositorService.isMango) {
      const activeToplevel = ToplevelManager.activeToplevel;
      if (activeToplevel && activeToplevel.screens && activeToplevel.screens.length > 0) {
        Logger.d("CurrentScreenDetector", "Toplevel-based screen:", activeToplevel.screens[0].name);
        return activeToplevel.screens[0];  // Return ShellScreen directly
      }
    }

    // Convert monitor name to ShellScreen
    if (monitorName) {
      for (let i = 0; i < Quickshell.screens.length; i++) {
        if (Quickshell.screens[i].name === monitorName) {
          return Quickshell.screens[i];
        }
      }
    }

    return null;  // Fall back to cursor-based detection
  }

  Timer {
    id: screenDetectorDebounce
    running: false
    interval: 40
    onTriggered: {
      Logger.d("CurrentScreenDetector", "Screen debounced to:", root.detectedScreen?.name || "null");

      // Execute pending callback if any
      if (root.pendingCallback) {
        if (!Settings.data.general.allowPanelsOnScreenWithoutBar) {
          // If we explicitly disabled panels on screen without bar, check if bar is configured
          // for this screen, and fallback to primary screen if necessary
          var monitors = Settings.data.bar.monitors || [];
          const hasBar = monitors.length === 0 || monitors.includes(root.detectedScreen?.name);
          if (!hasBar) {
            root.detectedScreen = Quickshell.screens[0];
          }
        }

        Logger.d("CurrentScreenDetector", "Executing callback on screen:", root.detectedScreen.name);
        // Store callback locally and clear pendingCallback first to prevent deadlock
        // if the callback throws an error
        var callback = root.pendingCallback;
        root.pendingCallback = null;
        try {
          callback(root.detectedScreen);
        } catch (e) {
          Logger.e("CurrentScreenDetector", "Callback failed:", e);
        }
      }

      // Clean up
      screenDetectorLoader.active = false;
    }
  }

  // Invisible dummy PanelWindow to detect which screen should receive the action
  Loader {
    id: screenDetectorLoader
    active: false

    sourceComponent: PanelWindow {
      implicitWidth: 0
      implicitHeight: 0
      color: "transparent"
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-screen-detector"
      mask: Region {}

      onScreenChanged: root.screenDetected(screen)
    }
  }
}
