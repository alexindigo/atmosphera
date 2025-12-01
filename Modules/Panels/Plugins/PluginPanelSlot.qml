import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Noctalia
import qs.Services.UI

/**
* Generic plugin panel slot that can be reused for different plugins
*/
SmartPanel {
  id: root

  // Which plugin slot this is (1 or 2)
  property int slotNumber: 1

  // Currently loaded plugin ID (empty if no plugin using this slot)
  property string currentPluginId: ""

  // Plugin instance
  property var pluginInstance: null

  // Reference to the plugin content loader (set when panel content is created)
  property var contentLoader: null

  // Panel content is dynamically loaded
  panelContent: Component {
    Item {
      id: panelContainer

      // Required by SmartPanel for click-through mask
      readonly property var maskRegion: pluginContentItem

      // Panel properties expected by SmartPanel
      property bool allowAttach: true
      property real topPadding: 0
      property real bottomPadding: 0
      property real leftPadding: 0
      property real rightPadding: 0

      anchors.fill: parent

      // Dynamic plugin content
      Item {
        id: pluginContentItem
        anchors.fill: parent

        Loader {
          id: pluginContentLoader
          anchors.fill: parent
          active: false
        }
      }

      Component.onCompleted: {
        // Store reference to the loader so loadPluginPanel can access it
        root.contentLoader = pluginContentLoader;

        // Load plugin panel content if assigned
        if (root.currentPluginId !== "") {
          root.loadPluginPanel(root.currentPluginId);
        }
      }
    }
  }

  // Load a plugin's panel content
  function loadPluginPanel(pluginId) {
    if (!PluginService.isPluginLoaded(pluginId)) {
      Logger.w("PluginPanelSlot", "Plugin not loaded:", pluginId);
      return false;
    }

    var plugin = PluginService.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest) {
      Logger.w("PluginPanelSlot", "Plugin data not found:", pluginId);
      return false;
    }

    if (!plugin.manifest.provides.panel) {
      Logger.w("PluginPanelSlot", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    // Check if loader is available
    if (!root.contentLoader) {
      Logger.e("PluginPanelSlot", "Content loader not available yet");
      return false;
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var panelPath = pluginDir + "/" + plugin.manifest.entryPoints.panel;

    Logger.i("PluginPanelSlot", "Loading panel for plugin:", pluginId, "in slot", root.slotNumber);

    // Load the panel component
    var component = Qt.createComponent("file://" + panelPath);

    if (component.status === Component.Ready) {
      // Get plugin API
      var api = PluginService.getPluginAPI(pluginId);

      // Create instance with API
      root.contentLoader.active = true;
      root.contentLoader.sourceComponent = component;

      if (root.contentLoader.item) {
        // Inject plugin API
        if (root.contentLoader.item.hasOwnProperty("pluginApi")) {
          root.contentLoader.item.pluginApi = api;
        }

        root.pluginInstance = root.contentLoader.item;
        root.currentPluginId = pluginId;

        Logger.i("PluginPanelSlot", "Panel loaded for:", pluginId);
        return true;
      }
    } else if (component.status === Component.Error) {
      Logger.e("PluginPanelSlot", "Failed to load panel component:", component.errorString());
      return false;
    }

    return false;
  }

  // Unload current plugin panel
  function unloadPluginPanel() {
    if (root.currentPluginId === "") {
      return;
    }

    Logger.i("PluginPanelSlot", "Unloading panel from slot", root.slotNumber);

    if (root.contentLoader) {
      root.contentLoader.active = false;
      root.contentLoader.sourceComponent = null;
    }
    root.pluginInstance = null;
    root.currentPluginId = "";
  }

  // Register with PanelService
  Component.onCompleted: {
    PanelService.registerPanel(root);
  }
}
