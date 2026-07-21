import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
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

  function renderListenerRow(name, defaultValue, label, description, placeholder, onTest) {
    var row = listenerRowComp.createObject(column, {
                                             label: label,
                                             description: description,
                                             value: Settings.data.hooks.listeners[name] !== undefined ? Settings.data.hooks.listeners[name] : defaultValue
                                           });
    row.editClicked.connect(() => {
      openEdit(label, description, placeholder, row.value, newValue => {
        Settings.data.hooks.listeners[name] = newValue;
        Settings.saveImmediate();
        row.value = newValue;
      }, onTest);
    });
  }

  Component {
    id: listenerRowComp
    HookListenerRow {}
  }

  NText {
    text: I18n.tr("panels.hooks.listeners-description")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  ColumnLayout {
    id: column
    spacing: Style.marginS
    width: parent.width

    Component.onCompleted: {
      renderListenerRow("startup", Settings.data.hooks.startup || "", I18n.tr("panels.hooks.atmosphera-started-label"), I18n.tr("panels.hooks.atmosphera-started-description"), I18n.tr("panels.hooks.atmosphera-started-placeholder"), val => {});

      renderListenerRow("wallpaperChange", Settings.data.hooks.wallpaperChange || "", I18n.tr("panels.hooks.wallpaper-changed-label"), I18n.tr("panels.hooks.wallpaper-changed-description"), I18n.tr("panels.hooks.wallpaper-changed-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val.replace("$1", "test_wallpaper_path").replace("$2", "test_screen").replace("$3", "dark")]);
      });

      renderListenerRow("colorGeneration", Settings.data.hooks.colorGeneration || "", I18n.tr("panels.hooks.color-generation-label"), I18n.tr("panels.hooks.color-generation-description"), I18n.tr("panels.hooks.color-generation-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val.replace("$1", "dark")]);
      });

      renderListenerRow("darkModeChange", Settings.data.hooks.darkModeChange || "", I18n.tr("panels.hooks.theme-changed-label"), I18n.tr("panels.hooks.theme-changed-description"), I18n.tr("panels.hooks.theme-changed-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val.replace("$1", "true")]);
      });

      renderListenerRow("screenLock", Settings.data.hooks.screenLock || "", I18n.tr("panels.hooks.screen-lock-label"), I18n.tr("panels.hooks.screen-lock-description"), I18n.tr("panels.hooks.screen-lock-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val]);
      });

      renderListenerRow("screenUnlock", Settings.data.hooks.screenUnlock || "", I18n.tr("panels.hooks.screen-unlock-label"), I18n.tr("panels.hooks.screen-unlock-description"), I18n.tr("panels.hooks.screen-unlock-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val]);
      });

      renderListenerRow("performanceModeEnabled", Settings.data.hooks.performanceModeEnabled || "", I18n.tr("panels.hooks.performance-mode-enabled-label"), I18n.tr("panels.hooks.performance-mode-enabled-description"), I18n.tr("panels.hooks.performance-mode-enabled-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val]);
      });

      renderListenerRow("performanceModeDisabled", Settings.data.hooks.performanceModeDisabled || "", I18n.tr("panels.hooks.performance-mode-disabled-label"), I18n.tr("panels.hooks.performance-mode-disabled-description"), I18n.tr("panels.hooks.performance-mode-disabled-placeholder"), val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val]);
      });
    }
  }
}
