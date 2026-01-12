pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // A ref. to the lockScreen, so it's accessible from anywhere.
  property var lockScreen: null

  // Panels
  property var registeredPanels: ({})
  property var openedPanel: null
  property var closingPanel: null
  property bool closedImmediately: false

  // Overlay launcher state (separate from normal panels)
  property bool overlayLauncherOpen: false
  property var overlayLauncherScreen: null
  property var overlayLauncherCore: null  // Reference to LauncherCore when overlay is active
  // Brief window after panel opens where Exclusive keyboard is allowed on Hyprland
  // This allows text inputs to receive focus, then switches to OnDemand for click-to-close
  property bool isInitializingKeyboard: false
  signal willOpen
  signal didClose

  // Background slot assignments for dynamic panel background rendering
  // Slot 0: currently opening/open panel, Slot 1: closing panel
  property var backgroundSlotAssignments: [null, null]
  signal slotAssignmentChanged(int slotIndex, var panel)

  function assignToSlot(slotIndex, panel) {
    if (backgroundSlotAssignments[slotIndex] !== panel) {
      var newAssignments = backgroundSlotAssignments.slice();
      newAssignments[slotIndex] = panel;
      backgroundSlotAssignments = newAssignments;
      slotAssignmentChanged(slotIndex, panel);
    }
  }

  // Popup menu windows (one per screen) - used for both tray menus and context menus
  property var popupMenuWindows: ({})
  signal popupMenuWindowRegistered(var screen)

  // Register this panel (called after panel is loaded)
  function registerPanel(panel) {
    registeredPanels[panel.objectName] = panel;
    Logger.d("PanelService", "Registered panel:", panel.objectName);
  }

  // Register popup menu window for a screen
  function registerPopupMenuWindow(screen, window) {
    if (!screen || !window)
      return;
    var key = screen.name;
    popupMenuWindows[key] = window;
    Logger.d("PanelService", "Registered popup menu window for screen:", key);
    popupMenuWindowRegistered(screen);
  }

  // Get popup menu window for a screen
  function getPopupMenuWindow(screen) {
    if (!screen)
      return null;
    return popupMenuWindows[screen.name] || null;
  }

  // Returns a panel (loads it on-demand if not yet loaded)
  function getPanel(name, screen) {
    if (!screen) {
      Logger.d("PanelService", "missing screen for getPanel:", name);
      // If no screen specified, return the first matching panel
      for (var key in registeredPanels) {
        if (key.startsWith(name + "-")) {
          return registeredPanels[key];
        }
      }
      return null;
    }

    var panelKey = `${name}-${screen.name}`;

    // Check if panel is already loaded
    if (registeredPanels[panelKey]) {
      return registeredPanels[panelKey];
    }

    Logger.w("PanelService", "Panel not found:", panelKey);
    return null;
  }

  // Check if a panel exists
  function hasPanel(name) {
    return name in registeredPanels;
  }

  // Timer to switch from Exclusive to OnDemand keyboard focus on Hyprland
  Timer {
    id: keyboardInitTimer
    interval: 100
    repeat: false
    onTriggered: {
      root.isInitializingKeyboard = false;
    }
  }

  // Helper to keep only one panel open at any time
  function willOpenPanel(panel) {
    // Close overlay launcher if open
    if (overlayLauncherOpen) {
      overlayLauncherOpen = false;
      overlayLauncherScreen = null;
    }

    if (openedPanel && openedPanel !== panel) {
      // Move current panel to closing slot before closing it
      closingPanel = openedPanel;
      assignToSlot(1, closingPanel);
      openedPanel.close();
    }

    // Assign new panel to open slot
    openedPanel = panel;
    assignToSlot(0, panel);

    // Start keyboard initialization period (for Hyprland workaround)
    if (panel && panel.exclusiveKeyboard) {
      isInitializingKeyboard = true;
      keyboardInitTimer.restart();
    }

    // emit signal
    willOpen();
  }

  // Open launcher panel (handles both normal and overlay mode)
  function openLauncher(screen) {
    if (Settings.data.appLauncher.overviewLayer) {
      // Close any regular panel first
      if (openedPanel) {
        closingPanel = openedPanel;
        assignToSlot(1, closingPanel);
        openedPanel.close();
        openedPanel = null;
      }
      // Open overlay launcher
      overlayLauncherOpen = true;
      overlayLauncherScreen = screen;
      willOpen();
    } else {
      // Normal mode - use the SmartPanel
      var panel = getPanel("launcherPanel", screen);
      if (panel)
        panel.open();
    }
  }

  // Toggle launcher panel
  function toggleLauncher(screen) {
    if (Settings.data.appLauncher.overviewLayer) {
      if (overlayLauncherOpen && overlayLauncherScreen === screen) {
        closeOverlayLauncher();
      } else {
        openLauncher(screen);
      }
    } else {
      var panel = getPanel("launcherPanel", screen);
      if (panel)
        panel.toggle();
    }
  }

  // Close overlay launcher
  function closeOverlayLauncher() {
    if (overlayLauncherOpen) {
      overlayLauncherOpen = false;
      overlayLauncherScreen = null;
      didClose();
    }
  }

  // Close overlay launcher immediately (for app launches)
  function closeOverlayLauncherImmediately() {
    if (overlayLauncherOpen) {
      closedImmediately = true;
      overlayLauncherOpen = false;
      overlayLauncherScreen = null;
      didClose();
    }
  }

  // ==================== Unified Launcher API ====================
  // These methods work for both normal (SmartPanel) and overlay modes

  function isLauncherOpen(screen) {
    if (Settings.data.appLauncher.overviewLayer) {
      return overlayLauncherOpen && overlayLauncherScreen === screen;
    } else {
      var panel = getPanel("launcherPanel", screen);
      return panel ? panel.isPanelOpen : false;
    }
  }

  function getLauncherSearchText(screen) {
    if (Settings.data.appLauncher.overviewLayer) {
      return overlayLauncherCore ? overlayLauncherCore.searchText : "";
    } else {
      var panel = getPanel("launcherPanel", screen);
      return panel ? panel.searchText : "";
    }
  }

  function setLauncherSearchText(screen, text) {
    if (Settings.data.appLauncher.overviewLayer) {
      if (overlayLauncherCore)
        overlayLauncherCore.setSearchText(text);
    } else {
      var panel = getPanel("launcherPanel", screen);
      if (panel)
        panel.setSearchText(text);
    }
  }

  function openLauncherWithSearch(screen, searchText) {
    if (Settings.data.appLauncher.overviewLayer) {
      openLauncher(screen);
      // Set search text after core is ready
      Qt.callLater(() => {
                     if (overlayLauncherCore)
                     overlayLauncherCore.setSearchText(searchText);
                   });
    } else {
      var panel = getPanel("launcherPanel", screen);
      if (panel) {
        panel.open();
        panel.setSearchText(searchText);
      }
    }
  }

  function closeLauncher(screen) {
    if (Settings.data.appLauncher.overviewLayer) {
      closeOverlayLauncher();
    } else {
      var panel = getPanel("launcherPanel", screen);
      if (panel)
        panel.close();
    }
  }

  // Close any open panel (for general use)
  function closePanel() {
    if (overlayLauncherOpen) {
      closeOverlayLauncher();
    } else if (openedPanel && openedPanel.close) {
      openedPanel.close();
    }
  }

  function closedPanel(panel) {
    if (openedPanel && openedPanel === panel) {
      openedPanel = null;
      assignToSlot(0, null);
    }

    if (closingPanel && closingPanel === panel) {
      closingPanel = null;
      assignToSlot(1, null);
    }

    // Reset keyboard init state
    isInitializingKeyboard = false;
    keyboardInitTimer.stop();

    // emit signal
    didClose();
  }
}
