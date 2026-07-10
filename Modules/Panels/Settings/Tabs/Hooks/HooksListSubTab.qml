import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Control
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  enabled: Settings.data.hooks.enabled
  spacing: Style.marginL
  width: parent.width

  // Shared Edit Popup
  HookEditPopup {
    id: editPopup
    parent: Overlay.overlay
  }

  // Helper to open popup
  function openEdit(label, description, placeholder, value, onSave, onTest) {
    editPopup.hookLabel = label;
    editPopup.hookDescription = description;
    editPopup.hookPlaceholder = placeholder;
    editPopup.initialValue = value;

    // Disconnect previous signals
    try {
      editPopup.saved.disconnect(editPopup._savedSlot);
    } catch (e) {}
    try {
      editPopup.test.disconnect(editPopup._testSlot);
    } catch (e) {}

    // Define slots
    editPopup._savedSlot = onSave;
    editPopup._testSlot = onTest;

    // Connect new signals
    editPopup.saved.connect(editPopup._savedSlot);
    editPopup.test.connect(editPopup._testSlot);

    editPopup.open();
  }

  // Startup Hook
  HookRow {
    label: I18n.tr("panels.hooks.atmosphera-started-label")
    description: I18n.tr("panels.hooks.atmosphera-started-description")
    value: Settings.data.hooks.startup
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.atmosphera-started-placeholder"), value, newValue => {
      Settings.data.hooks.startup = newValue;
      Settings.saveImmediate();
    }, val => {
      HooksService.executeStartupHook();
    })
  }

  // Wallpaper Hook
  HookRow {
    label: I18n.tr("panels.hooks.wallpaper-changed-label")
    description: I18n.tr("panels.hooks.wallpaper-changed-description")
    value: Settings.data.hooks.wallpaperChange
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.wallpaper-changed-placeholder"), value, newValue => {
      Settings.data.hooks.wallpaperChange = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val.replace("$1", "test_wallpaper_path").replace("$2", "test_screen").replace("$3", "dark")]);
    })
  }

  // Color Generation Hook
  HookRow {
    label: I18n.tr("panels.hooks.color-generation-label")
    description: I18n.tr("panels.hooks.color-generation-description")
    value: Settings.data.hooks.colorGeneration
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.color-generation-placeholder"), value, newValue => {
      Settings.data.hooks.colorGeneration = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val.replace("$1", "dark")]);
    })
  }

  // Theme Hook
  HookRow {
    label: I18n.tr("panels.hooks.theme-changed-label")
    description: I18n.tr("panels.hooks.theme-changed-description")
    value: Settings.data.hooks.darkModeChange
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.theme-changed-placeholder"), value, newValue => {
      Settings.data.hooks.darkModeChange = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val.replace("$1", "true")]);
    })
  }

  // Screen Lock Hook
  HookRow {
    label: I18n.tr("panels.hooks.screen-lock-label")
    description: I18n.tr("panels.hooks.screen-lock-description")
    value: Settings.data.hooks.screenLock
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.screen-lock-placeholder"), value, newValue => {
      Settings.data.hooks.screenLock = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val]);
    })
  }

  // Screen Unlock Hook
  HookRow {
    label: I18n.tr("panels.hooks.screen-unlock-label")
    description: I18n.tr("panels.hooks.screen-unlock-description")
    value: Settings.data.hooks.screenUnlock
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.screen-unlock-placeholder"), value, newValue => {
      Settings.data.hooks.screenUnlock = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val]);
    })
  }

  // Performance Mode Enabled Hook
  HookRow {
    label: I18n.tr("panels.hooks.performance-mode-enabled-label")
    description: I18n.tr("panels.hooks.performance-mode-enabled-description")
    value: Settings.data.hooks.performanceModeEnabled
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.performance-mode-enabled-placeholder"), value, newValue => {
      Settings.data.hooks.performanceModeEnabled = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val]);
    })
  }

  // Performance Mode Disabled Hook
  HookRow {
    label: I18n.tr("panels.hooks.performance-mode-disabled-label")
    description: I18n.tr("panels.hooks.performance-mode-disabled-description")
    value: Settings.data.hooks.performanceModeDisabled
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.performance-mode-disabled-placeholder"), value, newValue => {
      Settings.data.hooks.performanceModeDisabled = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val]);
    })
  }

  // Session Hook
  HookRow {
    label: I18n.tr("panels.hooks.session-label")
    description: I18n.tr("panels.hooks.session-description")
    value: Settings.data.hooks.session
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.session-placeholder"), value, newValue => {
      Settings.data.hooks.session = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val + " test"]);
    })
  }

  // Desktop Left Click Hook
  HookRow {
    label: I18n.tr("panels.hooks.desktop-left-click-label")
    description: I18n.tr("panels.hooks.desktop-left-click-description")
    value: Settings.data.hooks.desktopLeftClick
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.desktop-left-click-placeholder"), value, newValue => {
      Settings.data.hooks.desktopLeftClick = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val.replace("$1", "test_screen").replace("$2", "0").replace("$3", "0")]);
    })
  }

  // Desktop Right Click Hook
  HookRow {
    label: I18n.tr("panels.hooks.desktop-right-click-label")
    description: I18n.tr("panels.hooks.desktop-right-click-description")
    value: Settings.data.hooks.desktopRightClick
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.desktop-right-click-placeholder"), value, newValue => {
      Settings.data.hooks.desktopRightClick = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val.replace("$1", "test_screen").replace("$2", "0").replace("$3", "0")]);
    })
  }

  // Desktop Middle Click Hook
  HookRow {
    label: I18n.tr("panels.hooks.desktop-middle-click-label")
    description: I18n.tr("panels.hooks.desktop-middle-click-description")
    value: Settings.data.hooks.desktopMiddleClick
    onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.desktop-middle-click-placeholder"), value, newValue => {
      Settings.data.hooks.desktopMiddleClick = newValue;
      Settings.saveImmediate();
    }, val => {
      if (val)
        Quickshell.execDetached(["sh", "-lc", val.replace("$1", "test_screen").replace("$2", "0").replace("$3", "0")]);
    })
  }
}
