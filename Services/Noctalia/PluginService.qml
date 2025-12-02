pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  signal pluginLoaded(string pluginId)
  signal pluginUnloaded(string pluginId)
  signal pluginEnabled(string pluginId)
  signal pluginDisabled(string pluginId)
  signal availablePluginsUpdated
  signal allPluginsLoaded

  // Loaded plugin instances
  property var loadedPlugins: ({}) // { pluginId: { component, instance, api } }

  // Available plugins from all sources (fetched from registries)
  property var availablePlugins: ([]) // Array of plugin metadata from all sources

  // Track active fetches
  property var activeFetches: ({})

  property bool initialized: false
  property bool pluginsFullyLoaded: false

  // Plugin container from shell.qml (for placing Main instances in graphics scene)
  property var pluginContainer: null

  // Listen for PluginRegistry to finish loading
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      if (!root.initialized) {
        root.init();
      }
    }
  }

  function init() {
    if (root.initialized) {
      Logger.d("PluginService", "Already initialized, skipping");
      return;
    }

    Logger.i("PluginService", "Initializing plugin system");
    root.initialized = true;

    // Debug: Check what's in PluginRegistry
    var allInstalled = PluginRegistry.getAllInstalledPluginIds();
    Logger.d("PluginService", "All installed plugins:", JSON.stringify(allInstalled));
    Logger.d("PluginService", "Plugin states:", JSON.stringify(PluginRegistry.pluginStates));

    // Load all enabled plugins
    var enabledIds = PluginRegistry.getEnabledPluginIds();
    Logger.i("PluginService", "Found", enabledIds.length, "enabled plugins:", JSON.stringify(enabledIds));

    for (var i = 0; i < enabledIds.length; i++) {
      Logger.d("PluginService", "Attempting to load plugin:", enabledIds[i]);
      var manifest = PluginRegistry.getPluginManifest(enabledIds[i]);
      if (manifest) {
        Logger.d("PluginService", "Manifest found for", enabledIds[i]);
        loadPlugin(enabledIds[i]);
      } else {
        Logger.e("PluginService", "No manifest for enabled plugin:", enabledIds[i]);
      }
    }

    // Mark plugins as fully loaded
    root.pluginsFullyLoaded = true;
    Logger.i("PluginService", "All plugins loaded");
    root.allPluginsLoaded();

    // Fetch available plugins from all sources
    refreshAvailablePlugins();
  }

  // Refresh available plugins from all sources
  function refreshAvailablePlugins() {
    Logger.i("PluginService", "Refreshing available plugins");
    root.availablePlugins = [];

    var sources = PluginRegistry.pluginSources;
    for (var i = 0; i < sources.length; i++) {
      fetchPluginRegistry(sources[i]);
    }
  }

  // Fetch plugin registry from a source
  function fetchPluginRegistry(source) {
    var rawUrl = source.url + "/raw/main/registry.json";
    var registryUrl = rawUrl.replace("github.com", "raw.githubusercontent.com");

    Logger.d("PluginService", "Fetching registry from:", registryUrl);

    var fetchProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "curl -L -s '${registryUrl}' || wget -q -O- '${registryUrl}'"]
        stdout: StdioCollector {}
      }
    `, root, "FetchRegistry_" + Date.now());

    activeFetches[source.url] = fetchProcess;

    fetchProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        try {
          var response = fetchProcess.stdout.text;
          var registry = JSON.parse(response);

          if (registry && registry.plugins && Array.isArray(registry.plugins)) {
            // Add source info to each plugin
            for (var i = 0; i < registry.plugins.length; i++) {
              var plugin = registry.plugins[i];
              plugin.source = source;

              // Check if already downloaded
              plugin.downloaded = PluginRegistry.isPluginDownloaded(plugin.id);
              plugin.enabled = PluginRegistry.isPluginEnabled(plugin.id);

              root.availablePlugins.push(plugin);
            }

            Logger.i("PluginService", "Loaded", registry.plugins.length, "plugins from", source.name);
            root.availablePluginsUpdated();
          }
        } catch (e) {
          Logger.e("PluginService", "Failed to parse registry from", source.name, ":", e);
        }
      } else {
        Logger.e("PluginService", "Failed to fetch registry from", source.name);
      }

      delete activeFetches[source.url];
      fetchProcess.destroy();
    });

    fetchProcess.running = true;
  }

  // Download and install a plugin
  function installPlugin(pluginMetadata, callback) {
    var pluginId = pluginMetadata.id;
    var source = pluginMetadata.source;

    Logger.i("PluginService", "Installing plugin:", pluginId, "from", source.name);

    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var repoUrl = source.url;
    var pluginPath = pluginId;

    // Download plugin folder from GitHub
    var downloadCmd = `
      mkdir -p '${pluginDir}' &&
      cd '${pluginDir}' &&
      (curl -L -s '${repoUrl}/archive/refs/heads/main.tar.gz' | tar -xz --strip-components=2 '*/main/${pluginPath}' ||
       wget -q -O- '${repoUrl}/archive/refs/heads/main.tar.gz' | tar -xz --strip-components=2 '*/main/${pluginPath}')
    `;

    var downloadProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "${downloadCmd}"]
      }
    `, root, "DownloadPlugin_" + pluginId);

    downloadProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.i("PluginService", "Downloaded plugin:", pluginId);

        // Load and validate manifest
        var manifestPath = pluginDir + "/manifest.json";
        loadManifest(manifestPath, function (success, manifest) {
          if (success) {
            var validation = PluginRegistry.validateManifest(manifest);
            if (validation.valid) {
              // Register plugin
              PluginRegistry.registerPlugin(manifest);
              Logger.i("PluginService", "Installed plugin:", pluginId);

              // Update available plugins list
              updatePluginInAvailable(pluginId, {
                                        downloaded: true
                                      });

              if (callback)
                callback(true, null);
            } else {
              Logger.e("PluginService", "Invalid manifest:", validation.error);
              if (callback)
                callback(false, "Invalid manifest: " + validation.error);
            }
          } else {
            Logger.e("PluginService", "Failed to load manifest for:", pluginId);
            if (callback)
              callback(false, "Failed to load manifest");
          }
        });
      } else {
        Logger.e("PluginService", "Failed to download plugin:", pluginId);
        if (callback)
          callback(false, "Download failed");
      }

      downloadProcess.destroy();
    });

    downloadProcess.running = true;
  }

  // Uninstall a plugin
  function uninstallPlugin(pluginId, callback) {
    Logger.i("PluginService", "Uninstalling plugin:", pluginId);

    // Disable and unload first
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      disablePlugin(pluginId);
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    var removeProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["rm", "-rf", "${pluginDir}"]
      }
    `, root, "RemovePlugin_" + pluginId);

    removeProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        PluginRegistry.unregisterPlugin(pluginId);
        Logger.i("PluginService", "Uninstalled plugin:", pluginId);

        // Update available plugins list
        updatePluginInAvailable(pluginId, {
                                  downloaded: false,
                                  enabled: false
                                });

        if (callback)
          callback(true, null);
      } else {
        Logger.e("PluginService", "Failed to uninstall plugin:", pluginId);
        if (callback)
          callback(false, "Failed to remove plugin files");
      }

      removeProcess.destroy();
    });

    removeProcess.running = true;
  }

  // Enable a plugin
  function enablePlugin(pluginId) {
    if (PluginRegistry.isPluginEnabled(pluginId)) {
      Logger.w("PluginService", "Plugin already enabled:", pluginId);
      return true;
    }

    if (!PluginRegistry.isPluginDownloaded(pluginId)) {
      Logger.e("PluginService", "Cannot enable: plugin not downloaded:", pluginId);
      return false;
    }

    PluginRegistry.setPluginEnabled(pluginId, true);
    loadPlugin(pluginId);
    updatePluginInAvailable(pluginId, {
                              enabled: true
                            });
    root.pluginEnabled(pluginId);
    return true;
  }

  // Disable a plugin
  function disablePlugin(pluginId) {
    if (!PluginRegistry.isPluginEnabled(pluginId)) {
      Logger.w("PluginService", "Plugin already disabled:", pluginId);
      return true;
    }

    PluginRegistry.setPluginEnabled(pluginId, false);
    unloadPlugin(pluginId);
    updatePluginInAvailable(pluginId, {
                              enabled: false
                            });
    root.pluginDisabled(pluginId);
    return true;
  }

  // Load a plugin
  function loadPlugin(pluginId) {
    if (root.loadedPlugins[pluginId]) {
      Logger.w("PluginService", "Plugin already loaded:", pluginId);
      return;
    }

    var manifest = PluginRegistry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot load: manifest not found for:", pluginId);
      return;
    }

    var pluginDir = PluginRegistry.getPluginDir(pluginId);

    Logger.i("PluginService", "Loading plugin:", pluginId);

    // Create plugin API object
    var pluginApi = createPluginAPI(pluginId, manifest);

    // Initialize plugin entry with API and manifest
    root.loadedPlugins[pluginId] = {
      barWidgetComponent: null,
      mainInstance: null,
      api: pluginApi,
      manifest: manifest
    };

    // Load Main.qml entry point if it exists
    if (manifest.entryPoints && manifest.entryPoints.main) {
      var mainPath = pluginDir + "/" + manifest.entryPoints.main;
      var mainComponent = Qt.createComponent("file://" + mainPath);

      if (mainComponent.status === Component.Ready) {
        // Get the plugin container from shell.qml (must be in graphics scene)
        if (!root.pluginContainer) {
          Logger.e("PluginService", "Plugin container not set. Shell must set PluginService.pluginContainer.");
          return;
        }

        // Instantiate Main.qml with container as parent (places it in graphics scene)
        var mainInstance = mainComponent.createObject(root.pluginContainer);

        if (mainInstance) {
          // Set pluginApi property after creation
          if (mainInstance.hasOwnProperty('pluginApi')) {
            mainInstance.pluginApi = pluginApi;
          } else {
            Logger.w("PluginService", "Main.qml for", pluginId, "should declare 'property var pluginApi: null'");
          }

          root.loadedPlugins[pluginId].mainInstance = mainInstance;
          Logger.i("PluginService", "Loaded Main.qml for plugin:", pluginId);
        } else {
          Logger.e("PluginService", "Failed to instantiate Main.qml for:", pluginId);
        }
      } else if (mainComponent.status === Component.Error) {
        Logger.e("PluginService", "Failed to load Main.qml:", mainComponent.errorString());
      }
    }

    // Load bar widget component if provided (don't instantiate - BarWidgetRegistry will do that)
    if (manifest.provides.barWidget && manifest.entryPoints.barWidget) {
      var widgetPath = pluginDir + "/" + manifest.entryPoints.barWidget;
      var widgetComponent = Qt.createComponent("file://" + widgetPath);

      if (widgetComponent.status === Component.Ready) {
        root.loadedPlugins[pluginId].barWidgetComponent = widgetComponent;

        // Register with BarWidgetRegistry
        BarWidgetRegistry.registerPluginWidget(pluginId, widgetComponent, manifest.metadata);
        Logger.i("PluginService", "Loaded bar widget for plugin:", pluginId);
      } else if (widgetComponent.status === Component.Error) {
        Logger.e("PluginService", "Failed to load bar widget component:", widgetComponent.errorString());
      }
    }

    Logger.i("PluginService", "Plugin loaded:", pluginId);
    root.pluginLoaded(pluginId);
  }

  // Unload a plugin
  function unloadPlugin(pluginId) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin) {
      Logger.w("PluginService", "Plugin not loaded:", pluginId);
      return;
    }

    Logger.i("PluginService", "Unloading plugin:", pluginId);

    // Unregister from BarWidgetRegistry
    if (plugin.manifest.provides.barWidget) {
      BarWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Destroy Main instance if any
    if (plugin.mainInstance) {
      plugin.mainInstance.destroy();
    }

    delete root.loadedPlugins[pluginId];
    root.pluginUnloaded(pluginId);
    Logger.i("PluginService", "Unloaded plugin:", pluginId);
  }

  // Create plugin API object
  function createPluginAPI(pluginId, manifest) {
    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);

    var api = Qt.createQmlObject(`
      import QtQuick

      QtObject {
        // Plugin-specific
        readonly property string pluginId: "${pluginId}"
        readonly property string pluginDir: "${pluginDir}"
        property var pluginSettings: ({})

        // IPC handlers storage
        property var ipcHandlers: ({})

        // Functions will be bound below
        property var saveSettings: null
        property var openPanel: null
        property var closePanel: null
      }
    `, root, "PluginAPI_" + pluginId);

    // Load plugin settings
    loadPluginSettings(pluginId, function (settings) {
      api.pluginSettings = settings;
    });

    // Bind functions
    api.saveSettings = function () {
      savePluginSettings(pluginId, api.pluginSettings);

      // Replace the entire pluginSettings object to trigger QML property bindings
      // Make a shallow copy so bindings detect the change
      api.pluginSettings = Object.assign({}, api.pluginSettings);
    };

    api.openPanel = function (screen) {
      // Open this plugin's panel on the specified screen
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening panel");
        return false;
      }
      return openPluginPanel(pluginId, screen);
    };

    api.closePanel = function (screen) {
      // Close this plugin's panel (find which slot it's in and close it)
      for (var slotNum = 1; slotNum <= 2; slotNum++) {
        var panelName = "pluginPanel" + slotNum;
        var panel = PanelService.getPanel(panelName, screen);
        if (panel && panel.currentPluginId === pluginId) {
          panel.close();
          return true;
        }
      }
      return false;
    };

    return api;
  }

  // Load plugin settings
  function loadPluginSettings(pluginId, callback) {
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);

    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${settingsFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadSettings_" + pluginId);

    readProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        try {
          var settings = JSON.parse(readProcess.stdout.text);
          callback(settings);
        } catch (e) {
          Logger.w("PluginService", "Failed to parse settings for", pluginId, "- using defaults");
          callback({});
        }
      } else {
        // File doesn't exist - use defaults
        callback({});
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Save plugin settings
  function savePluginSettings(pluginId, settings) {
    var settingsFile = PluginRegistry.getPluginSettingsFile(pluginId);
    var settingsJson = JSON.stringify(settings, null, 2);

    // Use heredoc delimiter pattern to avoid all escaping issues
    var delimiter = "PLUGIN_SETTINGS_EOF_" + Math.random().toString(36).substr(2, 9);
    var fileEsc = settingsFile.replace(/'/g, "'\\''");

    // Get parent directory and ensure it exists
    var settingsDir = settingsFile.substring(0, settingsFile.lastIndexOf('/'));
    var dirEsc = settingsDir.replace(/'/g, "'\\''");

    // Build the shell command with heredoc (create dir first)
    var writeCmd = "mkdir -p '" + dirEsc + "' && cat > '" + fileEsc + "' << '" + delimiter + "'\n" + settingsJson + "\n" + delimiter + "\n";

    Logger.d("PluginService", "Saving settings to:", settingsFile);
    Logger.d("PluginService", "Settings JSON:", settingsJson);

    // Use Quickshell.execDetached to execute the command (use array syntax)
    var pid = Quickshell.execDetached(["sh", "-c", writeCmd]);
    Logger.d("PluginService", "Write process started, PID:", pid);
  }

  // Load manifest from file
  function loadManifest(manifestPath, callback) {
    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${manifestPath}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadManifest_" + Date.now());

    readProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        try {
          var manifest = JSON.parse(readProcess.stdout.text);
          callback(true, manifest);
        } catch (e) {
          Logger.e("PluginService", "Failed to parse manifest:", e);
          callback(false, null);
        }
      } else {
        Logger.e("PluginService", "Failed to read manifest at:", manifestPath);
        callback(false, null);
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Update plugin metadata in available plugins list
  function updatePluginInAvailable(pluginId, updates) {
    for (var i = 0; i < root.availablePlugins.length; i++) {
      if (root.availablePlugins[i].id === pluginId) {
        for (var key in updates) {
          root.availablePlugins[i][key] = updates[key];
        }
        root.availablePluginsUpdated();
        break;
      }
    }
  }

  // Get plugin API for a loaded plugin
  function getPluginAPI(pluginId) {
    return root.loadedPlugins[pluginId]?.api || null;
  }

  // Check if plugin is loaded
  function isPluginLoaded(pluginId) {
    return !!root.loadedPlugins[pluginId];
  }

  // Open a plugin's panel (finds a free slot and loads the panel)
  function openPluginPanel(pluginId, screen) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot open panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.provides.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    // Try to find the plugin panel slot (pluginPanel1 or pluginPanel2)
    // Try slot 1 first, then slot 2
    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel) {
        // If this slot is already showing this plugin's panel, toggle it
        if (panel.currentPluginId === pluginId) {
          panel.toggle();
          return true;
        }

        // If this slot is empty, use it
        if (panel.currentPluginId === "") {
          // Open the panel first so the loader gets created
          panel.open();
          // Wait a brief moment for the panel to be fully created
          Qt.callLater(function () {
            panel.loadPluginPanel(pluginId);
          });
          return true;
        }
      }
    }

    // If both slots are occupied, use slot 1 (replace existing)
    var panel1 = PanelService.getPanel("pluginPanel1", screen);
    if (panel1) {
      panel1.unloadPluginPanel();
      panel1.open();
      Qt.callLater(function () {
        panel1.loadPluginPanel(pluginId);
      });
      return true;
    }

    Logger.e("PluginService", "Failed to find plugin panel slot");
    return false;
  }
}
