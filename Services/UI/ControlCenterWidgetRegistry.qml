pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.ControlCenter.Widgets

Singleton {
  id: root

  // Emitted after plugin widgets are registered/unregistered
  signal pluginWidgetRegistryUpdated

  // Widget registry object mapping widget names to components
  property var widgets: ({
                           "AirplaneMode": airplaneModeComponent,
                           "Bluetooth": bluetoothComponent,
                           "CustomButton": customButtonComponent,
                           "DarkMode": darkModeComponent,
                           "KeepAwake": keepAwakeComponent,
                           "NightLight": nightLightComponent,
                           "Notifications": notificationsComponent,
                           "PowerProfile": powerProfileComponent,
                           "WiFi": networkComponent,
                           "Network": networkComponent,
                           "AtmospheraPerformance": atmospheraPerformanceComponent,
                           "WallpaperSelector": wallpaperSelectorComponent
                         })

  property var widgetMetadata: ({
                                  "CustomButton": {
                                    "icon": "heart",
                                    "onClicked": "",
                                    "onRightClicked": "",
                                    "onMiddleClicked": "",
                                    "stateChecksJson": "[]",
                                    "generalTooltipText": "",
                                    "enableOnStateLogic": false,
                                    "showExecTooltip": true
                                  }
                                })

  property var cpuIntensiveWidgets: ["SystemStat"]

  // Component definitions - these are loaded once at startup
  property Component airplaneModeComponent: Component {
    AirplaneMode {}
  }
  property Component bluetoothComponent: Component {
    Bluetooth {}
  }
  property Component customButtonComponent: Component {
    CustomButton {}
  }
  property Component darkModeComponent: Component {
    DarkMode {}
  }
  property Component keepAwakeComponent: Component {
    KeepAwake {}
  }
  property Component nightLightComponent: Component {
    NightLight {}
  }
  property Component notificationsComponent: Component {
    Notifications {}
  }
  property Component powerProfileComponent: Component {
    PowerProfile {}
  }
  property Component networkComponent: Component {
    Network {}
  }
  property Component atmospheraPerformanceComponent: Component {
    AtmospheraPerformance {}
  }
  property Component wallpaperSelectorComponent: Component {
    WallpaperSelector {}
  }

  function init() {
    Logger.i("ControlCenterWidgetRegistry", "Service started");
  }

  // ------------------------------
  // Helper function to get widget component by name
  function getWidget(id) {
    return widgets[id] || null;
  }

  // Helper function to check if widget exists
  function hasWidget(id) {
    return id in widgets;
  }

  // Get list of available widget id
  function getAvailableWidgets() {
    return Object.keys(widgets);
  }

  // Helper function to check if widget has user settings
  function widgetHasUserSettings(id) {
    return widgetMetadata[id] !== undefined;
  }

  // ------------------------------
  // Plugin widget registration

  // Track plugin widgets separately
  property var pluginWidgets: ({})
  property var pluginWidgetMetadata: ({})

  // Register a plugin widget
  function registerPluginWidget(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("ControlCenterWidgetRegistry", "Cannot register plugin widget: invalid parameters");
      return false;
    }

    // Add plugin: prefix to avoid conflicts with core widgets
    var widgetId = "plugin:" + pluginId;

    // Publish new map objects so QML bindings on these maps re-evaluate.
    // Metadata is assigned before the component map.
    var nextPluginWidgetMetadata = Object.assign({}, pluginWidgetMetadata);
    nextPluginWidgetMetadata[widgetId] = metadata || {};
    pluginWidgetMetadata = nextPluginWidgetMetadata;

    var nextWidgetMetadata = Object.assign({}, widgetMetadata);
    nextWidgetMetadata[widgetId] = metadata || {};
    widgetMetadata = nextWidgetMetadata;

    var nextPluginWidgets = Object.assign({}, pluginWidgets);
    nextPluginWidgets[widgetId] = component;
    pluginWidgets = nextPluginWidgets;

    // Also add to main widgets object for unified access
    var nextWidgets = Object.assign({}, widgets);
    nextWidgets[widgetId] = component;
    widgets = nextWidgets;

    Logger.i("ControlCenterWidgetRegistry", "Registered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }

  // Unregister a plugin widget
  function unregisterPluginWidget(pluginId) {
    var widgetId = "plugin:" + pluginId;

    if (!pluginWidgets[widgetId]) {
      Logger.w("ControlCenterWidgetRegistry", "Plugin widget not registered:", widgetId);
      return false;
    }

    // Publish new map objects so QML bindings on these maps re-evaluate.
    // Metadata is assigned before the component map.
    var nextPluginWidgetMetadata = Object.assign({}, pluginWidgetMetadata);
    delete nextPluginWidgetMetadata[widgetId];
    pluginWidgetMetadata = nextPluginWidgetMetadata;

    var nextWidgetMetadata = Object.assign({}, widgetMetadata);
    delete nextWidgetMetadata[widgetId];
    widgetMetadata = nextWidgetMetadata;

    var nextPluginWidgets = Object.assign({}, pluginWidgets);
    delete nextPluginWidgets[widgetId];
    pluginWidgets = nextPluginWidgets;

    var nextWidgets = Object.assign({}, widgets);
    delete nextWidgets[widgetId];
    widgets = nextWidgets;

    Logger.i("ControlCenterWidgetRegistry", "Unregistered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }

  // Check if a widget is a plugin widget
  function isPluginWidget(id) {
    return id.startsWith("plugin:");
  }

  // Get list of plugin widget IDs
  function getPluginWidgets() {
    return Object.keys(pluginWidgets);
  }

  function isCpuIntensive(id) {
    if (pluginWidgetMetadata[id]?.cpuIntensive)
      return true;
    return cpuIntensiveWidgets.indexOf(id) >= 0;
  }
}
