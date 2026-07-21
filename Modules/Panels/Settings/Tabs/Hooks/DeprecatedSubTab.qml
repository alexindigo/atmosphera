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

  HookEditPopup {
    id: editPopup
    parent: Overlay.overlay
  }

  function openEdit(label, description, placeholder, value, onSave, onTest) {
    editPopup.hookLabel = label;
    editPopup.hookDescription = description;
    editPopup.hookPlaceholder = placeholder;
    editPopup.initialValue = value;
    try {
      editPopup.saved.disconnect(editPopup._savedSlot);
    } catch (e) {}
    try {
      editPopup.test.disconnect(editPopup._testSlot);
    } catch (e) {}
    editPopup._savedSlot = onSave;
    editPopup._testSlot = onTest;
    editPopup.saved.connect(editPopup._savedSlot);
    editPopup.test.connect(editPopup._testSlot);
    editPopup.open();
  }

  Rectangle {
    Layout.fillWidth: true
    color: Color.mSurfaceVariant
    radius: Style.radiusM
    Layout.preferredHeight: noticeText.implicitHeight + Style.marginL * 2

    NText {
      id: noticeText
      anchors.centerIn: parent
      width: parent.width - Style.marginL * 2
      text: I18n.tr("panels.hooks.deprecated-notice")
      wrapMode: Text.WordWrap
      pointSize: Style.fontSizeS
    }
  }

  ColumnLayout {
    spacing: Style.marginM
    width: parent.width

    // ─── session ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.session-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── wallpaperChange ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.wallpaper-changed-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── darkModeChange ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.theme-changed-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── screenLock ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.screen-lock-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── screenUnlock ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.screen-unlock-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── performanceModeEnabled ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.performance-mode-enabled-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── performanceModeDisabled ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.performance-mode-disabled-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── startup ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
      HookRow {
        label: I18n.tr("panels.hooks.atmosphera-started-label")
        description: I18n.tr("panels.hooks.atmosphera-started-description")
        value: Settings.data.hooks.startup
        onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.atmosphera-started-placeholder"), value, newValue => {
          Settings.data.hooks.startup = newValue;
          Settings.saveImmediate();
        }, val => {})
      }
      NText {
        text: I18n.tr("panels.hooks.atmosphera-started-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── colorGeneration ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.color-generation-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── desktopLeftClick ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.desktop-left-click-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── desktopRightClick ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.desktop-right-click-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── desktopMiddleClick ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
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
      NText {
        text: I18n.tr("panels.hooks.desktop-middle-click-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── idle.screenOffCommand (moved from Idle → Behavior) ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
      HookRow {
        label: I18n.tr("panels.hooks.screenoff-label")
        description: I18n.tr("panels.hooks.screenoff-description")
        value: Settings.data.idle.screenOffCommand
        onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.screenoff-placeholder"), value, newValue => {
          Settings.data.idle.screenOffCommand = newValue;
          Settings.saveImmediate();
        }, val => {
          if (val)
            Quickshell.execDetached(["sh", "-lc", val]);
        })
      }
      NText {
        text: I18n.tr("panels.hooks.idle-screen-off-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── idle.lockCommand (moved from Idle → Behavior) ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
      HookRow {
        label: I18n.tr("panels.hooks.lock-label")
        description: I18n.tr("panels.hooks.lock-description")
        value: Settings.data.idle.lockCommand
        onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.lock-placeholder"), value, newValue => {
          Settings.data.idle.lockCommand = newValue;
          Settings.saveImmediate();
        }, val => {
          if (val)
            Quickshell.execDetached(["sh", "-lc", val]);
        })
      }
      NText {
        text: I18n.tr("panels.hooks.idle-lock-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ─── idle.suspendCommand (moved from Idle → Behavior) ───
    ColumnLayout {
      spacing: Style.marginXS
      width: parent.width
      HookRow {
        label: I18n.tr("panels.hooks.suspend-label")
        description: I18n.tr("panels.hooks.suspend-description")
        value: Settings.data.idle.suspendCommand
        onEditClicked: openEdit(label, description, I18n.tr("panels.hooks.suspend-placeholder"), value, newValue => {
          Settings.data.idle.suspendCommand = newValue;
          Settings.saveImmediate();
        }, val => {
          if (val)
            Quickshell.execDetached(["sh", "-lc", val]);
        })
      }
      NText {
        text: I18n.tr("panels.hooks.idle-suspend-moved-to")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }
  }
}
