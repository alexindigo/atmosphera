pragma Singleton

import QtQuick
import Quickshell
import "../../Helpers/RecordListEditor.js" as Lists
import "../../Helpers/SectionWidgetCommands.js" as SectionCommands
import qs.Commons
import qs.Modules.DesktopWidgets.Widgets
import qs.Services.Plugins
import qs.Services.UI

Singleton {
  id: root

  // Transient state - not persisted, resets on shell restart
  property bool editMode: false

  // Signal emitted when plugin widgets are registered/unregistered
  signal pluginWidgetRegistryUpdated

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
  property Component systemStatComponent: Component {
    DesktopSystemStat {}
  }
  property Component audioVisualizerComponent: Component {
    DesktopAudioVisualizer {}
  }
  property Component appShortcutComponent: Component {
    DesktopAppShortcut {}
  }

  // Widget registry object mapping widget names to components
  // Created in Component.onCompleted to ensure Components are ready
  property var widgets: ({})

  // Explicit URLs for core widgets. Inline Component.url returns the parent
  // file's URL, so we need these for Loader.setSource() with initial properties.
  // Plugin widgets use their Component.url directly (loaded from actual files).
  readonly property string _widgetsDir: Quickshell.shellDir + "/Modules/DesktopWidgets/Widgets/"
  property var widgetUrls: ({})

  Component.onCompleted: {
    // Initialize widgets object after Components are ready
    var widgetsObj = {};
    widgetsObj["Clock"] = clockComponent;
    widgetsObj["MediaPlayer"] = mediaPlayerComponent;
    widgetsObj["Weather"] = weatherComponent;
    widgetsObj["SystemStat"] = systemStatComponent;
    widgetsObj["AudioVisualizer"] = audioVisualizerComponent;
    widgetsObj["AppShortcut"] = appShortcutComponent;
    widgets = widgetsObj;

    var urlsObj = {};
    urlsObj["Clock"] = _widgetsDir + "DesktopClock.qml";
    urlsObj["MediaPlayer"] = _widgetsDir + "DesktopMediaPlayer.qml";
    urlsObj["Weather"] = _widgetsDir + "DesktopWeather.qml";
    urlsObj["SystemStat"] = _widgetsDir + "DesktopSystemStat.qml";
    urlsObj["AudioVisualizer"] = _widgetsDir + "DesktopAudioVisualizer.qml";
    urlsObj["AppShortcut"] = _widgetsDir + "DesktopAppShortcut.qml";
    widgetUrls = urlsObj;

    Logger.i("DesktopWidgetRegistry", "Service started");
  }

  property var widgetSettingsMap: ({
                                     "Clock": "WidgetSettings/ClockSettings.qml",
                                     "MediaPlayer": "WidgetSettings/MediaPlayerSettings.qml",
                                     "Weather": "WidgetSettings/WeatherSettings.qml",
                                     "SystemStat": "WidgetSettings/SystemStatSettings.qml",
                                     "AudioVisualizer": "WidgetSettings/AudioVisualizerSettings.qml",
                                     "AppShortcut": "WidgetSettings/AppShortcutSettings.qml"
                                   })

  property var widgetMetadata: ({
                                  "Clock": {
                                    "showBackground": true,
                                    "roundedCorners": true,
                                    "clockStyle": "digital",
                                    "clockColor": "none",
                                    "useCustomFont": false,
                                    "customFont": "",
                                    "format": "HH:mm\\nd MMMM yyyy"
                                  },
                                  "MediaPlayer": {
                                    "showBackground": true,
                                    "roundedCorners": true,
                                    "visualizerType": "linear",
                                    "hideMode": "visible",
                                    "showButtons": true,
                                    "showAlbumArt": true,
                                    "showVisualizer": true
                                  },
                                  "Weather": {
                                    "showBackground": true,
                                    "roundedCorners": true
                                  },
                                  "SystemStat": {
                                    "showBackground": true,
                                    "roundedCorners": true,
                                    "statType": "CPU",
                                    "diskPath": "/",
                                    "layout": "bottom"
                                  },
                                  "AudioVisualizer": {
                                    "showBackground": true,
                                    "roundedCorners": true,
                                    "width": 320,
                                    "height": 72,
                                    "visualizerType": "linear",
                                    "hideWhenIdle": false,
                                    "colorName": "primary"
                                  },
                                  "AppShortcut": {
                                    "showBackground": false,
                                    "roundedCorners": true,
                                    "appId": "",
                                    "customLabel": "",
                                    "showLabel": false,
                                    "singleClick": true,
                                    "environmentVars": [],
                                    "params": [],
                                    "iconSource": "",
                                    "iconType": "auto"
                                  }
                                })

  property var cpuIntensiveWidgets: ["SystemStat", "AudioVisualizer"]

  // Plugin widget storage (mirroring BarWidgetRegistry pattern)
  property var pluginWidgets: ({})
  property var pluginWidgetMetadata: ({})

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
    return widgetMetadata[id] !== undefined;
  }

  function isCpuIntensive(id) {
    if (pluginWidgetMetadata[id]?.cpuIntensive)
      return true;
    return cpuIntensiveWidgets.indexOf(id) >= 0;
  }

  // Check if a widget is a plugin widget
  function isPluginWidget(id) {
    return id.startsWith("plugin:");
  }

  // Get list of plugin widget IDs
  function getPluginWidgets() {
    return Object.keys(pluginWidgets);
  }

  // Get display name for a widget ID
  function getWidgetDisplayName(widgetId) {
    if (widgetId.startsWith("plugin:")) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = Registry.getPluginManifest(pluginId);
      return manifest ? manifest.name : pluginId;
    }
    // Core widgets - return as-is (Clock, MediaPlayer, Weather, SystemStat)
    return widgetId;
  }

  // Register a plugin desktop widget
  function registerPluginWidget(pluginId, component, metadata) {
    if (!pluginId || !component) {
      Logger.e("DesktopWidgetRegistry", "Cannot register plugin widget: invalid parameters");
      return false;
    }

    var widgetId = "plugin:" + pluginId;

    // Create new objects to trigger QML property change detection.
    // Metadata is assigned before the component map.
    var newPluginMetadata = Object.assign({}, pluginWidgetMetadata);
    newPluginMetadata[widgetId] = metadata || {};
    pluginWidgetMetadata = newPluginMetadata;

    var newMetadata = Object.assign({}, widgetMetadata);
    newMetadata[widgetId] = Object.assign({}, {
                                            "showBackground": true
                                          }, metadata || {});
    widgetMetadata = newMetadata;

    var newPluginWidgets = Object.assign({}, pluginWidgets);
    newPluginWidgets[widgetId] = component;
    pluginWidgets = newPluginWidgets;

    // Also add to main widgets object for unified access - reassign to trigger change
    var newWidgets = Object.assign({}, widgets);
    newWidgets[widgetId] = component;
    widgets = newWidgets;

    Logger.i("DesktopWidgetRegistry", "Registered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }

  // Unregister a plugin desktop widget
  function unregisterPluginWidget(pluginId) {
    var widgetId = "plugin:" + pluginId;

    if (!pluginWidgets[widgetId]) {
      Logger.w("DesktopWidgetRegistry", "Plugin widget not registered:", widgetId);
      return false;
    }

    // Create new objects without the widget to trigger QML property change detection.
    // Metadata is assigned before the component map.
    var newPluginMetadata = Object.assign({}, pluginWidgetMetadata);
    delete newPluginMetadata[widgetId];
    pluginWidgetMetadata = newPluginMetadata;

    var newMetadata = Object.assign({}, widgetMetadata);
    delete newMetadata[widgetId];
    widgetMetadata = newMetadata;

    var newPluginWidgets = Object.assign({}, pluginWidgets);
    delete newPluginWidgets[widgetId];
    pluginWidgets = newPluginWidgets;

    var newWidgets = Object.assign({}, widgets);
    delete newWidgets[widgetId];
    widgets = newWidgets;

    Logger.i("DesktopWidgetRegistry", "Unregistered plugin widget:", widgetId);
    root.pluginWidgetRegistryUpdated();
    return true;
  }

  function getWidgetsForMonitor(monitorName) {
    var monitors = Settings.data.desktopWidgets.monitorWidgets;
    for (var i = 0; i < monitors.length; ++i) {
      if (monitors[i].name === monitorName)
        return monitors[i].widgets || [];
    }
    return [];
  }

  function _widgetAddress(monitorName) {
    return [{field: "name", equals: monitorName}, {key: "widgets"}];
  }

  function _createListEditor(path, address, additionalLists) {
    return Settings.createRecordListEditor(path, address, additionalLists, {ensure: true});
  }

  // New rows are explicit input. Existing rows only cross field/transfer commands.
  function addWidget(monitorName, widgetData, callback) {
    var commands = root._createListEditor(["desktopWidgets", "monitorWidgets"], root._widgetAddress(monitorName));
    if (!commands)
      return false;
    var index = commands.initialValue.length;
    return commands.submit([{op: "insert", index: index, value: widgetData}], function (result) {
      commands.detach();
      if (typeof callback === "function")
        callback(result, index);
    });
  }

  function captureWidgetInteraction(monitorName, index, monitorNames) {
    var names = [monitorName].concat(monitorNames || []).filter(function (name, i, all) { return all.indexOf(name) === i; });
    var sections = names.map(function (name) {
      return {id: name, path: ["desktopWidgets", "monitorWidgets"], listAddress: root._widgetAddress(name), ensure: true,
        length: root.getWidgetsForMonitor(name).length};
    });
    return SectionCommands.capture({sections: sections, createEditor: root._createListEditor,
      transferFields: {x: 100, y: 100, scale: 1.0},
      later: function (callback) { Qt.callLater(callback); }, onChanged: function () {}}, monitorName, index);
  }

  // Retain this editor through component loading, saves, Retry and close cleanup.
  function createWidgetSettingsEditor(monitorName, index) {
    var commands = Settings.createRecordListEditor(["desktopWidgets", "monitorWidgets"], root._widgetAddress(monitorName));
    if (!commands || !Number.isSafeInteger(index) || index < 0 || index >= commands.initialValue.length) {
      if (commands)
        commands.detach();
      return null;
    }
    return {
      initialValue: Settings.store.copyValue(commands.initialValue[index]),
      submit: function (fields, callback) {
        var edits = fields && typeof fields === "object" && !Array.isArray(fields) ? Object.keys(fields).filter(function (key) {
          return key !== "id";
        }).map(function (key) { return {op: "set", index: index, field: key, value: fields[key]}; }) : [];
        return commands.submit(edits, function (result) {
          if (result.status === "admitted" && result.refreshState === "current") {
            Settings.saveResult(callback);
          } else if (typeof callback === "function") {
            callback({status: "failed", error: result.error || {code: "list-edit-conflict"}});
          }
        });
      },
      removeIfUnassigned: function (callback) {
        var row = commands.initialValue[index];
        if (!row || row.id !== "AppShortcut" || row.appId)
          return false;
        // The command fence, not a later row lookup, decides whether cleanup is safe.
        return commands.submit([{op: "remove", index: index}], callback);
      },
      detach: function () { commands.detach(); }
    };
  }

  function updateWidgetData(monitorName, widgetIndex, properties, callback, capturedEditor) {
    var editor = capturedEditor || root.createWidgetSettingsEditor(monitorName, widgetIndex);
    if (!editor)
      return false;
    return editor.submit(properties, function (result) {
      if (!capturedEditor)
        editor.detach();
      if (typeof callback === "function")
        callback(result);
    });
  }

  property var currentSettingsDialog: null
  property bool _settingsOpening: false

  function openWidgetSettings(screen, widgetIndex, widgetId, widgetData, onCloseCallback, anchorX, anchorY, anchorW, anchorH, capturedEditor) {
    if (!widgetId || !screen) {
      return;
    }

    if (root.currentSettingsDialog || root._settingsOpening) {
      if (root.currentSettingsDialog)
        root.currentSettingsDialog.forceActiveFocus();
      if (capturedEditor)
        capturedEditor.detach();
      return;
    }

    var hasSettings = false;
    if (root.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = Registry.getPluginManifest(pluginId);
      if (manifest && manifest.entryPoints && (manifest.entryPoints.desktopWidgetSettings || manifest.entryPoints.settings)) {
        hasSettings = true;
      }
    } else {
      hasSettings = root.widgetSettingsMap[widgetId] !== undefined;
    }

    if (!hasSettings) {
      Logger.w("DesktopWidgetRegistry", "Widget does not have settings:", widgetId);
      return;
    }

    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (!popupMenuWindow) {
      Logger.e("DesktopWidgetRegistry", "No popup menu window found for screen");
      return;
    }

    if (popupMenuWindow.hideDynamicMenu) {
      popupMenuWindow.hideDynamicMenu();
    }

    var editor = capturedEditor || root.createWidgetSettingsEditor(screen.name, widgetIndex);
    if (!editor)
      return;
    root._settingsOpening = true;
    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml");

    function instantiateAndOpen() {
      var dialogProps = {
        "widgetIndex": widgetIndex,
        "widgetData": editor.initialValue,
        "settingsEditor": editor,
        "widgetId": widgetId,
        "sectionId": screen.name,
        "screen": screen
      };
      if (anchorX !== undefined && anchorX >= 0) {
        dialogProps.anchorX = anchorX;
        dialogProps.anchorY = anchorY !== undefined ? anchorY : 0;
        dialogProps.anchorW = anchorW !== undefined ? anchorW : 0;
        dialogProps.anchorH = anchorH !== undefined ? anchorH : 0;
      }
      var dialog = component.createObject(popupMenuWindow.dialogParent, dialogProps);
      root._settingsOpening = false;

      if (dialog) {
        root.currentSettingsDialog = dialog;
        dialog.closed.connect(() => {
          if (root.currentSettingsDialog === dialog) {
            root.currentSettingsDialog = null;
          }
          dialog.destroy();

          // Optional close callback — used for post-dismiss cleanup (e.g. delete empty widget)
          if (typeof onCloseCallback === "function") {
            onCloseCallback(screen, widgetIndex, widgetId, editor);
          }
          editor.detach();
        });
        popupMenuWindow.showDialog(dialog);
        dialog.open();
      } else {
        editor.detach();
        Logger.e("DesktopWidgetRegistry", "Failed to create widget settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      root._settingsOpening = false;
      editor.detach();
      Logger.e("DesktopWidgetRegistry", "Error loading settings dialog component:", component.errorString());
    } else {
      component.statusChanged.connect(() => {
        if (component.status === Component.Ready) {
          instantiateAndOpen();
        } else if (component.status === Component.Error) {
          root._settingsOpening = false;
          editor.detach();
          Logger.e("DesktopWidgetRegistry", "Error loading settings dialog component:", component.errorString());
        }
      });
    }
  }
}
