pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets.Widgets

Singleton {
  id: root

  // Component definitions
  property Component clockComponent: Component {
    DesktopClock {}
  }
  property Component mediaPlayerComponent: Component {
    DesktopMediaPlayer {}
  }
  property Component weatherComponent: Component {
    DesktopWeather {}
  }

  // Widget registry object mapping widget names to components
  // Created in Component.onCompleted to ensure Components are ready
  property var widgets: ({})

  Component.onCompleted: {
    // Initialize widgets object after Components are ready
    var widgetsObj = {};
    widgetsObj["Clock"] = clockComponent;
    widgetsObj["MediaPlayer"] = mediaPlayerComponent;
    widgetsObj["Weather"] = weatherComponent;
    widgets = widgetsObj;

    Logger.i("DesktopWidgetRegistry", "Service started");
    Logger.d("DesktopWidgetRegistry", "Available widgets:", Object.keys(widgets));
    Logger.d("DesktopWidgetRegistry", "Clock component:", clockComponent ? "exists" : "null");
    Logger.d("DesktopWidgetRegistry", "MediaPlayer component:", mediaPlayerComponent ? "exists" : "null");
    Logger.d("DesktopWidgetRegistry", "Weather component:", weatherComponent ? "exists" : "null");
    Logger.d("DesktopWidgetRegistry", "Widgets object keys:", Object.keys(widgets));
    Logger.d("DesktopWidgetRegistry", "Widgets object values check - Clock:", widgets["Clock"] ? "exists" : "null");
  }

  property var widgetSettingsMap: ({
                                     "Clock": "WidgetSettings/ClockSettings.qml",
                                     "MediaPlayer": "WidgetSettings/MediaPlayerSettings.qml",
                                     "Weather": "WidgetSettings/WeatherSettings.qml"
                                   })

  property var widgetMetadata: ({
                                  "Clock": {
                                    "allowUserSettings": true,
                                    "showBackground": true
                                  },
                                  "MediaPlayer": {
                                    "allowUserSettings": true,
                                    "showBackground": true,
                                    "visualizerType": ""
                                  },
                                  "Weather": {
                                    "allowUserSettings": true,
                                    "showBackground": true
                                  }
                                })

  function init() {
    Logger.i("DesktopWidgetRegistry", "Service started");
  }

  // Helper function to get widget component by name
  function getWidget(id) {
    return widgets[id] || null;
  }

  // Helper function to check if widget exists
  function hasWidget(id) {
    return id in widgets;
  }

  // Get list of available widget ids
  function getAvailableWidgets() {
    var keys = Object.keys(widgets);
    Logger.d("DesktopWidgetRegistry", "getAvailableWidgets() called, returning:", keys);
    return keys;
  }

  // Helper function to check if widget has user settings
  function widgetHasUserSettings(id) {
    return (widgetMetadata[id] !== undefined) && (widgetMetadata[id].allowUserSettings === true);
  }

  // Check if a widget is a plugin widget (desktop widgets don't support plugins yet)
  function isPluginWidget(id) {
    return false;
  }

  // Get list of plugin widget IDs (empty for now)
  function getPluginWidgets() {
    return [];
  }
}
