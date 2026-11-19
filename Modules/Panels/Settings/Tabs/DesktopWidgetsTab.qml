import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings.DesktopWidgets
import qs.Services.Compositor
import qs.Services.Plugins
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  // The containing panel exposes closeRequested; it is not a QQuickItem member.
  function _panelAncestor(): var { return root.parent; }

  // Available widgets model - declared early so Repeater delegates can access it
  property alias availableWidgetsModel: availableWidgets
  ListModel {
    id: availableWidgets
  }

  // Listen for plugin widget registration/unregistration
  Connections {
    target: DesktopWidgetRegistry
    function onPluginWidgetRegistryUpdated() {
      updateAvailableWidgetsModel();
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.enabled-label")
    description: I18n.tr("panels.desktop-widgets.enabled-description")
    checked: Settings.data.desktopWidgets.enabled
    defaultValue: Settings.getDefaultValue("desktopWidgets.enabled")
    onToggled: checked => Settings.data.desktopWidgets.enabled = checked
  }

  NToggle {
    Layout.fillWidth: true
    enabled: Settings.data.desktopWidgets.enabled
    label: I18n.tr("panels.desktop-widgets.overview-enabled-label")
    description: I18n.tr("panels.desktop-widgets.overview-enabled-description")
    checked: Settings.data.desktopWidgets.overviewEnabled
    defaultValue: Settings.getDefaultValue("desktopWidgets.overviewEnabled")
    onToggled: checked => Settings.data.desktopWidgets.overviewEnabled = checked
  }

  ColumnLayout {
    enabled: Settings.data.desktopWidgets.enabled

    NLabel {
      description: I18n.tr("panels.desktop-widgets.cpu-intensive-note")
    }

    NButton {
      Layout.fillWidth: true
      text: I18n.tr("panels.desktop-widgets.add-app-shortcut-button")
      icon: Icon.add
      onClicked: _createAndEditAppShortcut()
    }

    NButton {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM
      Layout.bottomMargin: Style.marginM
      text: DesktopWidgetRegistry.editMode ? I18n.tr("panels.desktop-widgets.edit-mode-exit-button") : I18n.tr("panels.desktop-widgets.edit-mode-button-label")
      icon: Icon.edit
      onClicked: {
        DesktopWidgetRegistry.editMode = !DesktopWidgetRegistry.editMode;
        if (DesktopWidgetRegistry.editMode && Settings.data.ui.settingsPanelMode !== "window") {
          var item = root._panelAncestor();
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

    // One NSectionEditor per monitor
    Repeater {
      model: Quickshell.screens

      NSectionEditor {
        required property var modelData
        readonly property real compositorScale: {
          const info = CompositorService.displayScales[modelData.name];
          return (info && info.scale) ? info.scale : 1.0;
        }

        Layout.fillWidth: true
        sectionName: modelData.name
        sectionSubtitle: {
          // Format scale to 2 decimal places to prevent overly long text
          var formattedScale = compositorScale.toFixed(2);
          return "(" + modelData.width + "x" + modelData.height + " @ " + formattedScale + "x)";
        }

        sectionId: modelData.name
        captureWidgetInteraction: root.captureWidgetInteraction
        captureWidgetSettings: DesktopWidgetRegistry.createWidgetSettingsEditor
        screen: modelData
        settingsDialogComponent: Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml")
        widgetRegistry: DesktopWidgetRegistry
        widgetModel: getWidgetsForMonitor(modelData.name)
        availableWidgets: root.availableWidgetsModel
        availableSections: root.getScreenNames()
        sectionLabels: root.getScreenLabels()
        sectionIcons: root.getScreenIcons()
        draggable: false // Desktop widgets are positioned by X,Y, not list order
        crossSectionDraggable: true
        maxWidgets: -1
        onAddWidget: (widgetId, section) => _addWidgetToMonitor(modelData.name, widgetId)
        onRemoveWidget: (section, index) => _removeWidgetFromMonitor(modelData.name, index)
        onMoveWidget: (fromSection, index, toSection) => _moveWidgetToMonitor(fromSection, index, toSection)
        onUpdateWidgetSettings: (section, index, settings) => _updateWidgetSettingsForMonitor(modelData.name, index, settings)
        pluginSettingsEntryPoints: ["desktopWidgetSettings", "settings"]
        onOpenPluginSettingsRequested: (manifest, entryPoint, section, index) => root._openInstanceSettings(manifest, entryPoint, section, index)
      }
    }
  }

  NDivider {
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  DesktopMenuSubTab {}

  AtmoWidgetAppearance {
    blendStrength: Settings.data.desktopWidgets.iconBlendStrength
    blendStrengthDefault: 1.0
    onBlendStrengthEdited: v => Settings.data.desktopWidgets.iconBlendStrength = v

    hueAdjustment: Settings.data.desktopWidgets.iconHueAdjustment
    hueAdjustmentDefault: 0.0
    onHueAdjustmentEdited: v => Settings.data.desktopWidgets.iconHueAdjustment = v

    contentPadding: Settings.data.desktopWidgets.widgetContentPadding
    contentPaddingDefault: 0.0
    onContentPaddingEdited: v => Settings.data.desktopWidgets.widgetContentPadding = v
  }

  // Shared Plugin Settings Popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: false
  }

  Component.onCompleted: {
    // Use Qt.callLater to ensure DesktopWidgetRegistry is ready
    Qt.callLater(updateAvailableWidgetsModel);
  }

  // Helper to get screen names array
  function getScreenNames() {
    var names = [];
    for (var i = 0; i < Quickshell.screens.length; i++) {
      names.push(Quickshell.screens[i].name);
    }
    return names;
  }

  // Helper to get screen labels map (just screen names, NSectionEditor adds "Move to" prefix)
  function getScreenLabels() {
    var labels = {};
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screen = Quickshell.screens[i];
      labels[screen.name] = screen.name;
    }
    return labels;
  }

  // Helper to get screen icons map
  function getScreenIcons() {
    var icons = {};
    for (var i = 0; i < Quickshell.screens.length; i++) {
      icons[Quickshell.screens[i].name] = "device-desktop";
    }
    return icons;
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
        var displayName = widgetId;

        // Get plugin name for plugin widgets
        var isPlugin = false;
        if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
          isPlugin = true;
          var pluginId = widgetId.replace("plugin:", "");
          var manifest = Registry.getPluginManifest(pluginId);
          if (manifest && manifest.name) {
            displayName = manifest.name;
          }
        }

        // Add plugin badge first (with custom color)
        const badges = [];
        if (isPlugin) {
          badges.push({
                        "color": AtmoColor.mSecondary
                      });
        }
        if (DesktopWidgetRegistry.isCpuIntensive(widgetId)) {
          badges.push({
                        "color": AtmoColor.mSecondary
                      });
        }

        availableWidgets.append({
                                  "key": widgetId,
                                  "name": displayName,
                                  "badges": badges
                                });
      }
      Logger.d("DesktopWidgetsTab", "Available widgets model count:", availableWidgets.count);
    } catch (e) {
      Logger.e("DesktopWidgetsTab", "Error updating available widgets:", e, e.stack);
    }
  }

  // Get widgets for a specific monitor
  function getWidgetsForMonitor(monitorName) {
    return DesktopWidgetRegistry.getWidgetsForMonitor(monitorName);
  }

  function captureWidgetInteraction(monitorName, index) {
    return DesktopWidgetRegistry.captureWidgetInteraction(monitorName, index, root.getScreenNames());
  }

  function _addWidgetToMonitor(monitorName, widgetId) {
    var newWidget = {
      "id": widgetId
    };
    if (DesktopWidgetRegistry.widgetHasUserSettings(widgetId)) {
      var metadata = DesktopWidgetRegistry.widgetMetadata[widgetId];
      if (metadata) {
        Object.keys(metadata).forEach(function (key) {
          newWidget[key] = metadata[key];
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
    } else if (widgetId === "AudioVisualizer") {
      newWidget.x = 120;
      newWidget.y = 280;
    } else if (widgetId === "Weather") {
      newWidget.x = 100;
      newWidget.y = 300;
    } else {
      // Default position for plugin widgets
      newWidget.x = 150;
      newWidget.y = 150;
    }
    return DesktopWidgetRegistry.addWidget(monitorName, newWidget);
  }

  function _removeWidgetFromMonitor(monitorName, index) {
    var interaction = root.captureWidgetInteraction(monitorName, index);
    return interaction ? interaction.submit("remove", null, function () { interaction.detach(); }) : false;
  }

  function _updateWidgetSettingsForMonitor(monitorName, index, settings) {
    return DesktopWidgetRegistry.updateWidgetData(monitorName, index, settings);
  }

  // Opens the settings of the plugin instance at a desktop placement on `monitorName`.
  function _openInstanceSettings(manifest, settingsEntryPoint, monitorName, index) {
    var placement = {
      "kind": "desktop",
      "screenName": monitorName,
      "index": index
    };
    pluginSettingsDialog.openInstanceSettings(manifest, PluginInstances.apiFor(manifest.compositeKey || manifest.id, placement), settingsEntryPoint);
  }

  function _moveWidgetToMonitor(fromMonitor, index, toMonitor) {
    var interaction = DesktopWidgetRegistry.captureWidgetInteraction(fromMonitor, index, [toMonitor]);
    return interaction ? interaction.submit("move", toMonitor, function () { interaction.detach(); }) : false;
  }

  function _createAndEditAppShortcut() {
    // Add a new AppShortcut widget at screen center, then open its settings
    var monitorName = "";
    var firstScreen = Quickshell.screens && Quickshell.screens[0];
    if (firstScreen && firstScreen.name) {
      monitorName = firstScreen.name;
    }
    if (!monitorName) {
      Logger.w("DesktopWidgetsTab", "No screen available to create app shortcut");
      return;
    }

    var newWidget = {
      "id": "AppShortcut"
    };
    var metadata = DesktopWidgetRegistry.widgetMetadata["AppShortcut"];
    if (metadata) {
      Object.keys(metadata).forEach(function (key) {
        newWidget[key] = metadata[key];
      });
    }
    newWidget.x = firstScreen ? Math.round(firstScreen.width / 2) - 50 : 100;
    newWidget.y = firstScreen ? Math.round(firstScreen.height / 2) - 50 : 100;
    newWidget.scale = 1.0;
    newWidget.showBackground = true;
    newWidget.roundedCorners = true;

    return DesktopWidgetRegistry.addWidget(monitorName, newWidget, function (result, index) {
      if (result.status === "admitted" && result.refreshState === "current") {
        DesktopWidgetRegistry.openWidgetSettings(firstScreen, index, "AppShortcut", newWidget, function (scrn, wi, wid, editor) {
          editor.removeIfUnassigned();
        });
      }
    });
  }
}
