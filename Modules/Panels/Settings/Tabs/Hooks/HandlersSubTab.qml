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

  function getHandler(name) {
    try {
      return Settings.data.hooks.handlers[name] || ({
                                                      command: "",
                                                      exclusive: false
                                                    });
    } catch (e) {
      return ({
                command: "",
                exclusive: false
              });
    }
  }

  function renderHandlerRow(parent, name, label, description, placeholder) {
    var h = getHandler(name);
    var row = handlerRowComp.createObject(parent, {
                                            label: label,
                                            description: description,
                                            command: h.command || "",
                                            exclusive: h.exclusive || false
                                          });
    row.editClicked.connect(() => {
      var current = getHandler(name);
      openEdit(label, description, placeholder, current.command || "", newValue => {
        var handler = getHandler(name);
        handler.command = newValue;
        Settings.saveImmediate();
        row.command = newValue;
      }, val => {
        if (val)
          Quickshell.execDetached(["sh", "-lc", val]);
      });
    });
    row.exclusiveToggled.connect(checked => {
      var handler = getHandler(name);
      handler.exclusive = checked;
      Settings.saveImmediate();
    });
  }

  Component {
    id: handlerRowComp
    HookHandlerRow {}
  }

  NText {
    text: I18n.tr("panels.hooks.handlers-power-label")
    font.weight: Style.fontWeightBold
    pointSize: Style.fontSizeM
  }

  ColumnLayout {
    id: powerSection
    spacing: Style.marginS
    width: parent.width

    Component.onCompleted: {
      renderHandlerRow(powerSection, "suspendAction", I18n.tr("panels.hooks.suspend-label"), I18n.tr("panels.hooks.suspend-description"), I18n.tr("panels.hooks.suspend-placeholder"));
      renderHandlerRow(powerSection, "hibernateAction", I18n.tr("panels.hooks.hibernate-label"), I18n.tr("panels.hooks.hibernate-description"), I18n.tr("panels.hooks.hibernate-placeholder"));
      renderHandlerRow(powerSection, "lockAction", I18n.tr("panels.hooks.lock-label"), I18n.tr("panels.hooks.lock-description"), I18n.tr("panels.hooks.lock-placeholder"));
      renderHandlerRow(powerSection, "screenOffAction", I18n.tr("panels.hooks.screenoff-label"), I18n.tr("panels.hooks.screenoff-description"), I18n.tr("panels.hooks.screenoff-placeholder"));
      renderHandlerRow(powerSection, "shutdownAction", I18n.tr("panels.hooks.shutdown-label"), I18n.tr("panels.hooks.shutdown-description"), I18n.tr("panels.hooks.shutdown-placeholder"));
      renderHandlerRow(powerSection, "rebootAction", I18n.tr("panels.hooks.reboot-label"), I18n.tr("panels.hooks.reboot-description"), I18n.tr("panels.hooks.reboot-placeholder"));
      renderHandlerRow(powerSection, "userspaceRebootAction", I18n.tr("panels.hooks.userspacereboot-label"), I18n.tr("panels.hooks.userspacereboot-description"), I18n.tr("panels.hooks.userspacereboot-placeholder"));
      renderHandlerRow(powerSection, "rebootToUefiAction", I18n.tr("panels.hooks.reboottouefi-label"), I18n.tr("panels.hooks.reboottouefi-description"), I18n.tr("panels.hooks.reboottouefi-placeholder"));
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    text: I18n.tr("panels.hooks.handlers-desktop-label")
    font.weight: Style.fontWeightBold
    pointSize: Style.fontSizeM
  }

  ColumnLayout {
    id: desktopSection
    spacing: Style.marginS
    width: parent.width

    Component.onCompleted: {
      renderHandlerRow(desktopSection, "desktopLeftClick", I18n.tr("panels.hooks.desktop-left-click-label"), I18n.tr("panels.hooks.desktop-left-click-description"), I18n.tr("panels.hooks.desktop-left-click-placeholder"));
      renderHandlerRow(desktopSection, "desktopRightClick", I18n.tr("panels.hooks.desktop-right-click-label"), I18n.tr("panels.hooks.desktop-right-click-description"), I18n.tr("panels.hooks.desktop-right-click-placeholder"));
      renderHandlerRow(desktopSection, "desktopMiddleClick", I18n.tr("panels.hooks.desktop-middle-click-label"), I18n.tr("panels.hooks.desktop-middle-click-description"), I18n.tr("panels.hooks.desktop-middle-click-placeholder"));
    }
  }
}
