import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  // Selected monitor for widget configuration
  property string selectedMonitor: Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""

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
      Settings.data.desktopWidgets.editMode = true;
      if (Settings.data.ui.settingsPanelMode !== "window") {
        var item = root.parent;
        while (item) {
          if (item.closeRequested !== undefined) {
            item.closeRequested();
            break;
          }
          item = item.parent;
        }
      }
    }
  }

  NDivider {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
  }

  // Monitor selector
  NHeader {
    visible: Settings.data.desktopWidgets.enabled && Quickshell.screens.length > 1
    label: I18n.tr("settings.desktop-widgets.monitor.section.label")
    description: I18n.tr("settings.desktop-widgets.monitor.section.description")
  }

  NComboBox {
    visible: Settings.data.desktopWidgets.enabled && Quickshell.screens.length > 1
    Layout.fillWidth: true
    model: {
      var screens = [];
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screen = Quickshell.screens[i];
        var compositorScale = CompositorService.getDisplayScale(screen.name);
        screens.push({
                       "key": screen.name,
                       "name": screen.name + " (" + screen.width + "x" + screen.height + " @ " + compositorScale + "x)"
                     });
      }
      return screens;
    }
    currentKey: root.selectedMonitor
    onSelected: key => root.selectedMonitor = key
  }

  // Desktop Widgets Section
  NSectionEditor {
    visible: Settings.data.desktopWidgets.enabled
    Layout.fillWidth: true
    sectionName: I18n.tr("settings.desktop-widgets.widgets.section.label")
    sectionId: "desktop"
    settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml")
    widgetRegistry: DesktopWidgetRegistry
    widgetModel: getWidgetsForMonitor(root.selectedMonitor)
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
        Qt.callLater(function () {
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

  // Get widgets for a specific monitor
  function getWidgetsForMonitor(monitorName) {
    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    for (var i = 0; i < monitorWidgets.length; i++) {
      if (monitorWidgets[i].name === monitorName) {
        return monitorWidgets[i].widgets || [];
      }
    }
    return [];
  }

  // Set widgets for a specific monitor
  function setWidgetsForMonitor(monitorName, widgets) {
    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();
    var found = false;
    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === monitorName) {
        newMonitorWidgets[i] = {
          "name": monitorName,
          "widgets": widgets
        };
        found = true;
        break;
      }
    }
    if (!found) {
      newMonitorWidgets.push({
                               "name": monitorName,
                               "widgets": widgets
                             });
    }
    Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
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
    var widgets = getWidgetsForMonitor(root.selectedMonitor).slice();
    widgets.push(newWidget);
    setWidgetsForMonitor(root.selectedMonitor, widgets);
  }

  function _removeWidget(index) {
    var widgets = getWidgetsForMonitor(root.selectedMonitor);
    if (index >= 0 && index < widgets.length) {
      var newArray = widgets.slice();
      newArray.splice(index, 1);
      setWidgetsForMonitor(root.selectedMonitor, newArray);
    }
  }

  function _reorderWidget(fromIndex, toIndex) {
    var widgets = getWidgetsForMonitor(root.selectedMonitor);
    if (fromIndex >= 0 && fromIndex < widgets.length && toIndex >= 0 && toIndex < widgets.length) {
      var newArray = widgets.slice();
      var item = newArray[fromIndex];
      newArray.splice(fromIndex, 1);
      newArray.splice(toIndex, 0, item);
      setWidgetsForMonitor(root.selectedMonitor, newArray);
    }
  }

  function _updateWidgetSettings(index, settings) {
    var widgets = getWidgetsForMonitor(root.selectedMonitor);
    if (index >= 0 && index < widgets.length) {
      var newArray = widgets.slice();
      newArray[index] = Object.assign({}, newArray[index], settings);
      setWidgetsForMonitor(root.selectedMonitor, newArray);
    }
  }
}
