import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

FloatingWindow {
  id: root

  title: "Atmosphera"
  minimumSize: Qt.size(840 * Style.uiScaleRatio, 910 * Style.uiScaleRatio)
  implicitWidth: Math.round(840 * Style.uiScaleRatio)
  implicitHeight: Math.round(910 * Style.uiScaleRatio)
  color: "transparent"

  visible: false

  // Register with SettingsPanelService
  Component.onCompleted: {
    SettingsPanelService.settingsWindow = root;
  }

  property bool isInitialized: false

  // Navigate to a specific tab and optional subtab.
  // Works whether the window is already visible or just becoming visible.
  function navigateTo(tab, subTab) {
    const tabId = tab !== undefined ? tab : 0;
    const subTabId = (subTab !== undefined && subTab !== null && subTab >= 0) ? subTab : -1;
    if (isInitialized) {
      settingsContent.navigateToTab(tabId, subTabId);
    } else {
      settingsContent.requestedTab = tabId;
      if (subTabId >= 0)
        settingsContent._pendingSubTab = subTabId;
      settingsContent.initialize();
      isInitialized = true;
      // Tab content persists in window mode; if no subtab specified and the
      // tab content is still loaded (same tab), reset to first subtab
      if (subTabId < 0 && settingsContent.activeTabContent)
        settingsContent.setSubTabIndex(0);
    }
  }

  // Navigate to a search result entry.
  // Works whether the window is already visible or just becoming visible.
  function navigateToEntry(entry) {
    if (isInitialized) {
      navigationTimer.entry = entry;
      navigationTimer.restart();
    } else {
      settingsContent.requestedTab = entry.tab;
      settingsContent.initialize();
      navigationTimer.entry = entry;
      navigationTimer.restart();
      isInitialized = true;
    }
  }

  Timer {
    id: navigationTimer
    interval: 0
    property var entry: null
    onTriggered: {
      if (root.visible)
        settingsContent.navigateToResult(entry);
    }
  }

  // Sync visibility with service
  onVisibleChanged: {
    if (visible) {
      SettingsPanelService.isWindowOpen = true;
    } else {
      isInitialized = false;
      SettingsPanelService.isWindowOpen = false;
    }
  }

  // Keyboard shortcuts
  NScopedShortcut {
    scope: root.contentItem
    sequence: "Escape"
    enabled: !PanelService.isKeybindRecording
    onActivated: SettingsPanelService.closeWindow()
  }

  NScopedShortcut {
    scope: root.contentItem
    sequence: "Tab"
    enabled: !PanelService.isKeybindRecording
    onActivated: settingsContent.selectNextTab()
  }

  NScopedShortcut {
    scope: root.contentItem
    sequence: "Backtab"
    enabled: !PanelService.isKeybindRecording
    onActivated: settingsContent.selectPreviousTab()
  }

  Instantiator {
    model: Settings.data.general.keybinds.keyUp || []
    NScopedShortcut {
      required property string modelData
      scope: root.contentItem
      sequence: modelData
      enabled: !PanelService.isKeybindRecording
      onActivated: {
        if (settingsContent.searchText.trim() !== "")
          settingsContent.searchSelectPrevious();
        else
          settingsContent.scrollUp();
      }
    }
  }

  Instantiator {
    model: Settings.data.general.keybinds.keyDown || []
    NScopedShortcut {
      required property string modelData
      scope: root.contentItem
      sequence: modelData
      enabled: !PanelService.isKeybindRecording
      onActivated: {
        if (settingsContent.searchText.trim() !== "")
          settingsContent.searchSelectNext();
        else
          settingsContent.scrollDown();
      }
    }
  }

  // Main content
  Rectangle {
    anchors.fill: parent
    color: Qt.alpha(AtmoColor.mSurface, Style.effectivePanelOpacity)
    radius: Style.radiusL

    SettingsContent {
      id: settingsContent
      anchors.fill: parent
      onCloseRequested: SettingsPanelService.closeWindow()
    }
  }
}
