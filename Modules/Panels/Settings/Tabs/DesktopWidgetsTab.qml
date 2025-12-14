import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  NHeader {
    label: I18n.tr("settings.desktop-widgets.general.section.label")
    description: I18n.tr("settings.desktop-widgets.general.section.description")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.enabled.label")
    description: I18n.tr("settings.desktop-widgets.enabled.description")
    checked: Settings.data.desktopWidgets.enabled
    onToggled: checked => Settings.data.desktopWidgets.enabled = checked
  }

  NButton {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
    text: I18n.tr("settings.desktop-widgets.edit-mode.button.label")
    icon: "edit"
    onClicked: {
      Settings.data.desktopWidgets.editMode = true
      if (Settings.data.ui.settingsPanelMode !== "window") {
        var item = root.parent
        while (item) {
          if (item.closeRequested !== undefined) {
            item.closeRequested()
            break
          }
          item = item.parent
        }
      }
    }
  }

  NDivider {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
  }

  // Desktop Widgets Section
  NSectionEditor {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
    sectionName: I18n.tr("settings.desktop-widgets.widgets.section.label")
    sectionId: "desktop"
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml")
    widgetRegistry: DesktopWidgetRegistry
    widgetModel: Settings.data.desktopWidgets.widgets
    availableWidgets: availableWidgets
    maxWidgets: -1
    onAddWidget: (widgetId, section) => _addWidget(widgetId)
    onRemoveWidget: (section, index) => _removeWidget(index)
    onReorderWidget: (section, fromIndex, toIndex) => _reorderWidget(fromIndex, toIndex)
    onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettings(index, settings)
    onMoveWidget: (fromSection, index, toSection) => {} // Not needed for desktop widgets
  }

  // Available widgets model - must be a ListModel with id, not a property
  ListModel {
    id: availableWidgets
  }

  Component.onCompleted: {
    // Use Qt.callLater to ensure DesktopWidgetRegistry is ready
    Qt.callLater(updateAvailableWidgetsModel);
  }

  function updateAvailableWidgetsModel() {
    availableWidgets.clear();
    try {
      if (typeof DesktopWidgetRegistry === "undefined" || !DesktopWidgetRegistry) {
        Logger.e("DesktopWidgetsTab", "DesktopWidgetRegistry is not available");
        // Retry after a short delay
        Qt.callLater(function() {
          if (typeof DesktopWidgetRegistry !== "undefined" && DesktopWidgetRegistry) {
            updateAvailableWidgetsModel();
          }
        });
        return;
      }
      var widgetIds = DesktopWidgetRegistry.getAvailableWidgets();
      Logger.d("DesktopWidgetsTab", "Found widgets:", widgetIds, "count:", widgetIds ? widgetIds.length : 0);
      if (!widgetIds || widgetIds.length === 0) {
        Logger.w("DesktopWidgetsTab", "No widgets found in registry");
        return;
      }
      for (var i = 0; i < widgetIds.length; i++) {
        var widgetId = widgetIds[i];
        availableWidgets.append({
                                  "key": widgetId,
                                  "name": widgetId
                                });
      }
      Logger.d("DesktopWidgetsTab", "Available widgets model count:", availableWidgets.count);
    } catch (e) {
      Logger.e("DesktopWidgetsTab", "Error updating available widgets:", e, e.stack);
    }
  }

  function _addWidget(widgetId) {
    var newWidget = {
      "id": widgetId
    };
    if (DesktopWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = DesktopWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          if (key !== "allowUserSettings") {
            newWidget[key] = metadata[key];
          }
        });
      }
    }
    // Set default positions
    if (widgetId === "Clock") {
      newWidget.x = 50;
      newWidget.y = 50;
    } else if (widgetId === "MediaPlayer") {
      newWidget.x = 100;
      newWidget.y = 200;
    } else if (widgetId === "Weather") {
      newWidget.x = 100;
      newWidget.y = 300;
    }
    var widgets = Settings.data.desktopWidgets.widgets.slice();
    widgets.push(newWidget);
    Settings.data.desktopWidgets.widgets = widgets;
  }

  function _removeWidget(index) {
    if (index >= 0 && index < Settings.data.desktopWidgets.widgets.length) {
      var newArray = Settings.data.desktopWidgets.widgets.slice();
      newArray.splice(index, 1);
      Settings.data.desktopWidgets.widgets = newArray;
    }
  }

  function _reorderWidget(fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < Settings.data.desktopWidgets.widgets.length && 
        toIndex >= 0 && toIndex < Settings.data.desktopWidgets.widgets.length) {
      var newArray = Settings.data.desktopWidgets.widgets.slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);
      Settings.data.desktopWidgets.widgets = newArray;
    }
  }

  function _updateWidgetSettings(index, settings) {
    if (index >= 0 && index < Settings.data.desktopWidgets.widgets.length) {
      var newArray = Settings.data.desktopWidgets.widgets.slice();
      newArray[index] = Object.assign({}, newArray[index], settings);
      Settings.data.desktopWidgets.widgets = newArray;
    }
  }
}
