import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI

// ------------------------------
// MainScreen for each screen (manages bar + all panels)
// Wrapped in Loader to optimize memory - only loads when screen needs it
Variants {
  model: Quickshell.screens
  delegate: Item {
    id: screenRoot

    required property ShellScreen modelData

    property bool shouldBeActive: {
      if (!modelData || !modelData.name) {
        return false;
      }

      let shouldLoad = true;
      if (!Settings.data.general.allowPanelsOnScreenWithoutBar) {
        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        shouldLoad = monitors.length === 0 || monitors.includes(modelData?.name);
      }

      if (shouldLoad) {
        Logger.d("AllScreens", "Screen activated: ", modelData?.name);
      }
      return shouldLoad;
    }

    property bool windowLoaded: false

    // ============================
    // Bar auto-hide state (per screen)
    // ============================

    // Whether auto-hide is enabled for the bar
    property bool barAutoHide: Settings.data.bar.autoHide === true

    // Hidden state of the bar content (animated)
    property bool barHidden: barAutoHide

    // Hover state for bar content and peek window
    property bool barHovered: false
    property bool barPeekHovered: false

    // Keep bar visible while any panel or popup from the bar is open (global)
    readonly property bool barHoldOpen: PanelService.hasOpenedPopup || (PanelService.openedPanel && ((PanelService.openedPanel.visible === true) || (PanelService.openedPanel.active === true)))

    // Control whether the BarContentWindow is loaded at all
    // Start loaded so BarService.registerBar fires
    property bool barLoaded: true

    // Respect global animation toggle: no delays when animations are disabled
    readonly property int barHideDelay: Settings.data.general.animationDisabled ? 0 : 500
    readonly property int barShowDelay: Settings.data.general.animationDisabled ? 0 : 120
    readonly property int barHideAnimationDuration: Style.animationNormal
    readonly property int barShowAnimationDuration: Style.animationNormal

    // React when the auto-hide setting changes
    Connections {
      target: Settings.data.bar
      function onAutoHideChanged() {
        screenRoot.barAutoHide = Settings.data.bar.autoHide === true;
        if (screenRoot.barAutoHide) {
          screenRoot.barHidden = true;
          barShowTimer.stop();
          barHideTimer.stop();
          barUnloadTimer.restart();
        } else {
          screenRoot.barHidden = false;
          barShowTimer.stop();
          barHideTimer.stop();
          barUnloadTimer.stop();
          screenRoot.barLoaded = true;
        }
      }
    }

    // When hover state changes, manage show/hide timers
    onBarHoveredChanged: {
      if (!barAutoHide)
        return;
      if (barHovered) {
        barShowTimer.stop();
        barHideTimer.stop();
        barUnloadTimer.stop();
        barLoaded = true;
        barHidden = false;
      } else if (!barPeekHovered && !barHoldOpen) {
        barHideTimer.restart();
      }
    }

    // Timers for reveal/hide
    Timer {
      id: barShowTimer
      interval: screenRoot.barShowDelay
      repeat: false
      onTriggered: {
        screenRoot.barLoaded = true;
        screenRoot.barHidden = false;
        barUnloadTimer.stop();
      }
    }

    Timer {
      id: barHideTimer
      interval: screenRoot.barHideDelay
      repeat: false
      onTriggered: {
        if (screenRoot.barAutoHide && !screenRoot.barPeekHovered && !screenRoot.barHovered && !screenRoot.barHoldOpen) {
          screenRoot.barHidden = true;
          barUnloadTimer.restart();
        }
      }
    }

    // After hide animation, unload the window so it doesn't intercept input
    Timer {
      id: barUnloadTimer
      interval: screenRoot.barHideAnimationDuration
      repeat: false
      onTriggered: {
        if (screenRoot.barAutoHide && !screenRoot.barPeekHovered && !screenRoot.barHovered && !screenRoot.barHoldOpen) {
          screenRoot.barLoaded = false;
        }
      }
    }

    // React to panel / popup lifecycle to keep the bar visible during interactions
    Connections {
      target: PanelService
      // Any panel about to open -> show bar and cancel hides
      function onWillOpen() {
        if (!screenRoot.barAutoHide)
          return;
        barShowTimer.stop();
        barHideTimer.stop();
        screenRoot.barLoaded = true;
        screenRoot.barHidden = false;
      }
      // Popups opening/closing -> start/stop hide timer appropriately
      function onPopupChanged() {
        if (!screenRoot.barAutoHide)
          return;
        if (PanelService.hasOpenedPopup) {
          barShowTimer.stop();
          barHideTimer.stop();
          screenRoot.barLoaded = true;
          screenRoot.barHidden = false;
        } else if (!screenRoot.barHovered && !screenRoot.barPeekHovered && !screenRoot.barHoldOpen) {
          barHideTimer.restart();
        }
      }
      // Track when the main panel closes (openedPanel becomes null)
      function onOpenedPanelChanged() {
        if (!screenRoot.barAutoHide)
          return;
        if (PanelService.openedPanel !== null) {
          barShowTimer.stop();
          barHideTimer.stop();
          screenRoot.barLoaded = true;
          screenRoot.barHidden = false;
        } else if (!screenRoot.barHovered && !screenRoot.barPeekHovered && !PanelService.hasOpenedPopup) {
          barHideTimer.restart();
        }
      }
    }

    // Also listen to the current panel's own visible/active changes
    Connections {
      target: PanelService.openedPanel
      enabled: screenRoot.barAutoHide
      function onVisibleChanged() {
        if (!PanelService.openedPanel)
          return;
        if ((PanelService.openedPanel.visible === true) || (PanelService.openedPanel.active === true)) {
          barShowTimer.stop();
          barHideTimer.stop();
          screenRoot.barLoaded = true;
          screenRoot.barHidden = false;
        } else if (!screenRoot.barHovered && !screenRoot.barPeekHovered && !PanelService.hasOpenedPopup) {
          barHideTimer.restart();
        }
      }
      function onActiveChanged() {
        onVisibleChanged();
      }
    }

    // Main Screen loader - Bar and panels backgrounds
    Loader {
      id: windowLoader
      active: parent.shouldBeActive && PluginService.pluginsFullyLoaded
      asynchronous: false

      property ShellScreen loaderScreen: modelData

      onLoaded: {
        // Signal that window is loaded so exclusion zone can be created
        parent.windowLoaded = true;
      }

      sourceComponent: MainScreen {
        screen: windowLoader.loaderScreen
        autoHideContext: screenRoot
      }
    }

    // Bar content in separate windows to prevent fullscreen redraws
    Loader {
      id: barWindowLoader
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        var allowOnScreen = monitors.length === 0 || monitors.includes(modelData?.name);
        if (!allowOnScreen)
          return false;

        // Only load the bar content window when auto-hide is disabled
        // or when the bar is currently marked as loaded
        if (parent.barAutoHide && !parent.barLoaded)
          return false;

        return true;
      }
      asynchronous: false

      sourceComponent: BarContentWindow {
        screen: modelData
        autoHideContext: screenRoot
      }

      onLoaded: {
        Logger.d("AllScreens", "BarContentWindow created for", modelData?.name);
      }
    }

    // Peek window to reveal the bar when hovering at the screen edge
    Loader {
      id: barPeekLoader
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false;

        if (!parent.barAutoHide)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        return monitors.length === 0 || monitors.includes(modelData?.name);
      }
      asynchronous: false

      sourceComponent: PanelWindow {
        id: peekWindow
        screen: modelData
        color: Color.transparent
        focusable: false

        WlrLayershell.namespace: "noctalia-bar-peek-" + (screen?.name || "unknown")
        // Do not reserve space; keep as pure overlay so work area never changes
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: Settings.data.bar.position === "top"
          bottom: Settings.data.bar.position === "bottom"
          left: Settings.data.bar.position === "left"
          right: Settings.data.bar.position === "right"
        }

        // 1px reveal strip along the relevant edge
        implicitHeight: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? screen.height : 1
        implicitWidth: (Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom") ? screen.width : 1

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: {
            screenRoot.barPeekHovered = true;
            if (screenRoot.barAutoHide && screenRoot.barHidden) {
              barShowTimer.restart();
            }
          }
          onExited: {
            screenRoot.barPeekHovered = false;
            if (screenRoot.barAutoHide && !screenRoot.barHovered && !screenRoot.barHoldOpen) {
              barHideTimer.restart();
            }
          }
        }
      }

      onLoaded: {
        Logger.d("AllScreens", "Bar peek window created for", modelData?.name);
      }
    }

    // BarExclusionZone - created after MainScreen has fully loaded
    // Disabled when bar is hidden or not configured for this screen
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false;

        // When auto-hide is enabled, do not create an exclusion zone
        if (Settings.data.bar.autoHide === true)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        return monitors.length === 0 || monitors.includes(modelData?.name);
      }
      asynchronous: false

      sourceComponent: BarExclusionZone {
        screen: modelData
      }

      onLoaded: {
        Logger.d("AllScreens", "BarExclusionZone created for", modelData?.name);
      }
    }

    // PopupMenuWindow - reusable popup window for both tray menus and context menus
    // Disabled when bar is hidden or not configured for this screen
    Loader {
      active: {
        if (!parent.windowLoaded || !parent.shouldBeActive || !BarService.isVisible)
          return false;

        // Check if bar is configured for this screen
        var monitors = Settings.data.bar.monitors || [];
        return monitors.length === 0 || monitors.includes(modelData?.name);
      }
      asynchronous: false

      sourceComponent: PopupMenuWindow {
        screen: modelData
      }

      onLoaded: {
        Logger.d("AllScreens", "PopupMenuWindow created for", modelData?.name);
      }
    }
  }
}
