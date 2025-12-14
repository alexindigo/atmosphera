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

  // Available widgets model - declared early so Repeater delegates can access it
  property alias availableWidgetsModel: availableWidgets
  ListModel {
    id: availableWidgets
  }

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

  // One NSectionEditor per monitor
  Repeater {
    model: Settings.data.desktopWidgets.enabled ? Quickshell.screens : []

    NSectionEditor {
      required property var modelData

      Layout.fillWidth: true
      sectionName: {
        var compositorScale = CompositorService.getDisplayScale(modelData.name);
        return modelData.name + " (" + modelData.width + "x" + modelData.height + " @ " + compositorScale + "x)";
      }
      sectionId: modelData.name
      settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml")
      widgetRegistry: DesktopWidgetRegistry
      widgetModel: getWidgetsForMonitor(modelData.name)
      availableWidgets: root.availableWidgetsModel
      availableSections: [] // No sections to move between - hides move menu items
      draggable: false // Desktop widgets are positioned by X,Y, not list order
      maxWidgets: -1
      onAddWidget: (widgetId, section) => _addWidgetToMonitor(modelData.name, widgetId)
      onRemoveWidget: (section, index) => _removeWidgetFromMonitor(modelData.name, index)
      onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsForMonitor(modelData.name, index, settings)
    }
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

  function _addWidgetToMonitor(monitorName, widgetId) {
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
    var widgets = getWidgetsForMonitor(monitorName).slice();
    widgets.push(newWidget);
    setWidgetsForMonitor(monitorName, widgets);
  }

  function _removeWidgetFromMonitor(monitorName, index) {
    var widgets = getWidgetsForMonitor(monitorName);
    if (index >= 0 && index < widgets.length) {
      var newArray = widgets.slice();
      newArray.splice(index, 1);
      setWidgetsForMonitor(monitorName, newArray);
    }
  }

  function _updateWidgetSettingsForMonitor(monitorName, index, settings) {
    var widgets = getWidgetsForMonitor(monitorName);
    if (index >= 0 && index < widgets.length) {
      var newArray = widgets.slice();
      newArray[index] = Object.assign({}, newArray[index], settings);
      setWidgetsForMonitor(monitorName, newArray);
    }
  }
}
