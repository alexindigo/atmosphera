pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/sha256.js" as Crypto
import qs.Commons

Singleton {
  id: root

  readonly property string pluginsDir: Settings.configDir + "plugins"
  readonly property string pluginsFile: Settings.configDir + "plugins.json"

  readonly property int currentVersion: 2

  Component.onCompleted: {
    ensurePluginsDirectory();
    bootstrap();
  }

  // Generate a short hash (6 characters) from a source URL
  function generateSourceHash(sourceUrl) {
    var hash = Crypto.sha256(sourceUrl);
    return hash.substring(0, 6);
  }

  // Generate composite key: plain ID for null/empty URLs, "hash:id" for everything else
  function generateCompositeKey(pluginId, sourceUrl) {
    if (!sourceUrl) {
      return pluginId;
    }
    var hash = generateSourceHash(sourceUrl);
    return hash + ":" + pluginId;
  }

  // Parse composite key back to components
  function parseCompositeKey(compositeKey) {
    var colonIndex = compositeKey.indexOf(":");
    if (colonIndex === -1 || colonIndex > 6) {
      return {
        sourceHash: null,
        pluginId: compositeKey
      };
    }
    return {
      sourceHash: compositeKey.substring(0, colonIndex),
      pluginId: compositeKey.substring(colonIndex + 1)
    };
  }

  // Get source name by URL
  function getSourceNameByUrl(sourceUrl) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === sourceUrl) {
        return root.pluginSources[i].name;
      }
    }
    return null;
  }

  // Check if the source URL is from the official/main plugin registry
  function isMainSource(sourceUrl) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === sourceUrl) {
        return root.pluginSources[i].isOfficial === true;
      }
    }
    return false;
  }

  // Get source name by hash
  function getSourceNameByHash(hash) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (generateSourceHash(root.pluginSources[i].url) === hash) {
        return root.pluginSources[i].name;
      }
    }
    return null;
  }

  // Get source URL from plugin state
  function getPluginSourceUrl(compositeKey) {
    var state = root.pluginStates[compositeKey];
    return state ? state.sourceUrl : null;
  }

  // Signals
  signal pluginsChanged

  // In-memory plugin cache (populated by scanning disk)
  property var installedPlugins: ({}) // { pluginId: manifest }
  property var pluginStates: ({}) // { pluginId: { enabled: bool } }
  property var pluginSources: [] // Array of { name, url }
  property var pluginLoadVersions: ({}) // { pluginId: versionNumber } - for cache busting

  // Track async loading
  property int pendingManifests: 0

  // File storage (minimal - only states and sources)
  property FileView pluginsFileView: FileView {
    id: pluginsFileView
    path: ""

    adapter: JsonAdapter {
      id: adapter
      property int version: root.currentVersion
      property var states: ({})
      property list<var> sources: []
    }

    onLoaded: {
      Logger.i("PluginRegistry", "Loaded plugin states from:", path);
      root.pluginStates = adapter.states || {};
      root.pluginSources = adapter.sources || [];

      var needsSave = false;
      for (var i = 0; i < root.pluginSources.length; i++) {
        var src = root.pluginSources[i];
        if (!src.url && src.path) {
          src.url = "file://" + src.path;
          delete src.path;
          needsSave = true;
        }
      }

      if (needsSave) {
        root.save();
      }

      root.migratePluginData();
      scanPluginFolder();
    }

    onLoadFailed: function (error) {
      Logger.w("PluginRegistry", "Failed to load plugins.json, will create it:", error);
      root.pluginStates = {};
      root.pluginSources = [];
      root.scanPluginFolder();
    }
  }

  function init() {
    Logger.d("PluginRegistry", "Initialized");
    // Force instantiation of PluginService to set up signal listener
    PluginService.initialized;
  }

  function migratePluginData() {
    var needsSave = false;

    for (var pluginId in root.pluginStates) {
      if (root.pluginStates[pluginId].sourceUrl === undefined) {
        Logger.i("PluginRegistry", "Migrating plugin data to v2 (adding sourceUrl)");
        var newStates = {};
        for (var id in root.pluginStates) {
          newStates[id] = {
            enabled: root.pluginStates[id].enabled,
            sourceUrl: root.pluginStates[id].sourceUrl || null
          };
        }
        root.pluginStates = newStates;
        needsSave = true;
        break;
      }
    }

    if (needsSave) {
      root.save();
      Logger.i("PluginRegistry", "Migration complete");
    }
  }

  // Ensure plugins directory exists
  function ensurePluginsDirectory() {
    var mkdirProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["mkdir", "-p", "${root.pluginsDir}"]
      }
    `, root, "MkdirPlugins");

    mkdirProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.d("PluginRegistry", "Plugins directory ensured:", root.pluginsDir);
      } else {
        Logger.e("PluginRegistry", "Failed to create plugins directory");
      }
      mkdirProcess.destroy();
    });

    mkdirProcess.running = true;
  }

  // Bootstrap bundled plugins on first run — copies from system dir to user config
  // and writes seeded plugins.json with composite keys (hash:id) for all 3 bundled plugins.
  function bootstrap() {
    var probeProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "test -f '${root.pluginsFile}' && echo EXISTS || echo MISSING"]
        stdout: StdioCollector {}
      }
    `, root, "BootstrapProbe");

    probeProcess.exited.connect(function () {
      var out = (String(probeProcess.stdout.text || "")).trim();
      if (out === "EXISTS") {
        Logger.d("PluginRegistry", "Plugins file exists, skipping bootstrap");
        pluginsFileView.path = root.pluginsFile;
        probeProcess.destroy();
        return;
      }

      Logger.i("PluginRegistry", "First run — bootstrapping bundled plugins");

      var sourceUrl = "file://" + Quickshell.shellDir + "/Plugins";
      var hash = root.generateSourceHash(sourceUrl);
      var bundledPlugins = ["noctalia-icons-legacy", "atmosphera-icons", "atmosphera-wallpapers", "demo-custom-lockscreen"];
      var pluginId, compositeKey, targetDir, srcDir;
      var pending = 0;

      for (var i = 0; i < bundledPlugins.length; i++) {
        pluginId = bundledPlugins[i];
        compositeKey = hash + ":" + pluginId;
        targetDir = root.pluginsDir + "/" + compositeKey;
        srcDir = Quickshell.shellDir + "/Plugins/" + pluginId;

        pending++;
        var copyProc = Qt.createQmlObject(`
          import QtQuick
          import Quickshell.Io
          Process {
            command: ["sh", "-c", "test -d '${targetDir}' || mkdir -p '${targetDir}' && cp -r '${srcDir}/.' '${targetDir}/'"]
          }
        `, root, "CopyPlugin_" + pluginId);

        copyProc.exited.connect((function (proc) {
          return function () {
            proc.destroy();
            pending--;
            if (pending === 0) {
              root.writeSeedJson(sourceUrl, hash);
            }
          };
        })(copyProc));

        copyProc.running = true;
      }

      probeProcess.destroy();
    });

    probeProcess.running = true;
  }

  // Write seeded plugins.json with composite keys for bundled plugins.
  // Uses a temporary FileView with declared JsonAdapter properties to avoid
  // the runtime-assignment persistence issue with failed-state adapters.
  function writeSeedJson(sourceUrl, hash) {
    var template = 'import QtQuick\n' + 'import Quickshell.Io\n' + 'import qs.Commons\n' + 'FileView {\n' + '  path: "' + root.pluginsFile + '"\n' + '  adapter: JsonAdapter {\n' + '    property int version: ' + root.currentVersion + '\n' + '    property var sources: [{"enabled":true,"name":"Built-in","url":"' + sourceUrl + '"}]\n'
        + '    property var states: ({\n' + '      "' + hash + ':noctalia-icons-legacy":     {"enabled":true,"sourceUrl":"' + sourceUrl + '"},\n' + '      "' + hash + ':atmosphera-icons":           {"enabled":true,"sourceUrl":"' + sourceUrl + '"},\n' + '      "' + hash + ':atmosphera-wallpapers":      {"enabled":true,"sourceUrl":"' + sourceUrl + '"},\n'
        + '      "' + hash + ':demo-custom-lockscreen":     {"enabled":true,"sourceUrl":"' + sourceUrl + '"}\n' + '    })\n' + '  }\n' + '  Component.onCompleted: { writeAdapter(); Qt.callLater(destroy) }\n' + '}';

    var writer = Qt.createQmlObject(template, root, "SeedPluginsWriter");
    Qt.callLater(function () {
      pluginsFileView.path = root.pluginsFile;
      writer.destroy();
    });
  }

  // Scan plugin folder to discover installed plugins (single process reads all manifests)
  function scanPluginFolder() {
    Logger.i("PluginRegistry", "Scanning plugin folder:", root.pluginsDir);

    var scanProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "for d in '${root.pluginsDir}'/*/; do [ -d \\"$d\\" ] || continue; [ -f \\"$d/manifest.json\\" ] || continue; echo \\"@@PLUGIN@@$(basename \\"$d\\")\\" ; cat \\"$d/manifest.json\\" ; done"]
        stdout: StdioCollector {}
        running: true
      }
    `, root, "ScanAllPlugins");

    scanProcess.exited.connect(function (exitCode) {
      var output = String(scanProcess.stdout.text || "");
      var sections = output.split("@@PLUGIN@@");
      var loadedCount = 0;

      for (var i = 1; i < sections.length; i++) {
        var section = sections[i];
        var newlineIdx = section.indexOf('\n');
        if (newlineIdx === -1)
          continue;

        var pluginId = section.substring(0, newlineIdx).trim();
        var manifestJson = section.substring(newlineIdx + 1).trim();

        if (!pluginId || !manifestJson)
          continue;

        try {
          var manifest = JSON.parse(manifestJson);
          var validation = validateManifest(manifest);

          if (validation.valid) {
            manifest.compositeKey = pluginId;
            root.installedPlugins[pluginId] = manifest;
            Logger.i("PluginRegistry", "Loaded plugin:", pluginId, "-", manifest.name);

            if (!root.pluginStates[pluginId]) {
              root.pluginStates[pluginId] = {
                enabled: false
              };
            }
            loadedCount++;
          } else {
            Logger.e("PluginRegistry", "Invalid manifest for", pluginId + ":", validation.error);
          }
        } catch (e) {
          Logger.e("PluginRegistry", "Failed to parse manifest for", pluginId + ":", e.toString());
        }
      }

      Logger.i("PluginRegistry", "All plugin manifests loaded. Total plugins:", loadedCount);
      root.pluginsChanged();
      scanProcess.destroy();
    });
  }

  // Load a single plugin's manifest from disk
  function loadPluginManifest(pluginId) {
    var manifestPath = root.pluginsDir + "/" + pluginId + "/manifest.json";

    var catProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${manifestPath}"]
        stdout: StdioCollector {}
        running: true
      }
    `, root, "LoadManifest_" + pluginId);

    catProcess.exited.connect(function (exitCode) {
      var output = String(catProcess.stdout.text || "");
      if (exitCode === 0 && output) {
        try {
          var manifest = JSON.parse(output);
          var validation = validateManifest(manifest);

          if (validation.valid) {
            manifest.compositeKey = pluginId;
            root.installedPlugins[pluginId] = manifest;
            Logger.i("PluginRegistry", "Loaded plugin:", pluginId, "-", manifest.name);

            // Ensure state exists (default to disabled)
            if (!root.pluginStates[pluginId]) {
              root.pluginStates[pluginId] = {
                enabled: false
              };
            }
          } else {
            Logger.e("PluginRegistry", "Invalid manifest for", pluginId + ":", validation.error);
          }
        } catch (e) {
          Logger.e("PluginRegistry", "Failed to parse manifest for", pluginId + ":", e.toString());
        }
      } else {
        Logger.d("PluginRegistry", "No manifest found for:", pluginId);
      }

      // Decrement pending count and emit signal when all are done
      root.pendingManifests--;
      Logger.d("PluginRegistry", "Pending manifests remaining:", root.pendingManifests);
      if (root.pendingManifests === 0) {
        var installedIds = Object.keys(root.installedPlugins);
        Logger.i("PluginRegistry", "All plugin manifests loaded. Total plugins:", installedIds.length);
        Logger.d("PluginRegistry", "Installed plugin IDs:", JSON.stringify(installedIds));
        root.pluginsChanged();
      }

      catProcess.destroy();
    });
  }

  // Save registry to disk (only states and sources)
  function save() {
    adapter.version = root.currentVersion;
    adapter.states = root.pluginStates;
    adapter.sources = root.pluginSources;

    Qt.callLater(() => {
      pluginsFileView.writeAdapter();
      Logger.d("PluginRegistry", "Plugin states saved");
    });
  }

  // Enable/disable a plugin
  function setPluginEnabled(pluginId, enabled) {
    if (!root.installedPlugins[pluginId]) {
      Logger.w("PluginRegistry", "Cannot set state for non-existent plugin:", pluginId);
      return;
    }

    if (!root.pluginStates[pluginId]) {
      root.pluginStates[pluginId] = {
        enabled: enabled
      };
    } else {
      root.pluginStates[pluginId].enabled = enabled;
    }

    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Plugin", pluginId, enabled ? "enabled" : "disabled");
  }

  // Check if plugin is enabled
  function isPluginEnabled(pluginId) {
    return root.pluginStates[pluginId]?.enabled || false;
  }

  // Check if plugin is downloaded/installed
  function isPluginDownloaded(pluginId) {
    return pluginId in root.installedPlugins;
  }

  // Get plugin manifest from cache
  function getPluginManifest(pluginId) {
    return root.installedPlugins[pluginId] || null;
  }

  // Get ALL installed plugin IDs (discovered from disk)
  function getAllInstalledPluginIds() {
    return Object.keys(root.installedPlugins);
  }

  // Get enabled plugin IDs only
  function getEnabledPluginIds() {
    return Object.keys(root.pluginStates).filter(function (id) {
      return root.pluginStates[id].enabled === true;
    });
  }

  // Register a plugin (add to installed plugins after download)
  // sourceUrl is required for new plugins to generate composite key
  function registerPlugin(manifest, sourceUrl) {
    var compositeKey = generateCompositeKey(manifest.id, sourceUrl);
    manifest.compositeKey = compositeKey;
    root.installedPlugins[compositeKey] = manifest;

    if (!root.pluginStates[compositeKey]) {
      root.pluginStates[compositeKey] = {
        enabled: false,
        sourceUrl: sourceUrl || null
      };
    } else {
      root.pluginStates[compositeKey].sourceUrl = sourceUrl || null;
    }

    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Registered plugin:", compositeKey);
    return compositeKey;
  }

  // Unregister a plugin (remove from registry)
  function unregisterPlugin(pluginId) {
    delete root.pluginStates[pluginId];
    delete root.installedPlugins[pluginId];
    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Unregistered plugin:", pluginId);
  }

  // Increment plugin load version (for cache busting when plugin is updated)
  function incrementPluginLoadVersion(pluginId) {
    var versions = Object.assign({}, root.pluginLoadVersions);
    versions[pluginId] = (versions[pluginId] || 0) + 1;
    root.pluginLoadVersions = versions;
    Logger.d("PluginRegistry", "Incremented load version for", pluginId, "to", versions[pluginId]);
    return versions[pluginId];
  }

  // Remove plugin state (call after deleting plugin folder)
  function removePluginState(pluginId) {
    delete root.pluginStates[pluginId];
    delete root.installedPlugins[pluginId];
    save();
    root.pluginsChanged();
    Logger.i("PluginRegistry", "Removed plugin state:", pluginId);
  }

  // Add a plugin source
  function addPluginSource(name, url) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === url) {
        Logger.w("PluginRegistry", "Source already exists:", url);
        return false;
      }
    }

    // Create a new array to trigger property change notification
    var newSources = root.pluginSources.slice();
    newSources.push({
                      name: name,
                      url: url,
                      enabled: true
                    });
    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Added plugin source:", name);
    return true;
  }

  // Remove a plugin source
  function removePluginSource(url) {
    var newSources = [];
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url !== url) {
        newSources.push(root.pluginSources[i]);
      }
    }

    if (newSources.length === root.pluginSources.length) {
      Logger.w("PluginRegistry", "Source not found:", url);
      return false;
    }

    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Removed plugin source:", url);
    return true;
  }

  // Edit a plugin source (identify by oldUrl, update name and url)
  function editPluginSource(oldUrl, name, url) {
    var newSources = [];
    var found = false;
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === oldUrl) {
        newSources.push({
                          name: name,
                          url: url,
                          enabled: root.pluginSources[i].enabled !== false
                        });
        found = true;
      } else {
        newSources.push(root.pluginSources[i]);
      }
    }
    if (!found) {
      Logger.w("PluginRegistry", "Source not found:", oldUrl);
      return false;
    }
    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Edited plugin source:", name, url);
    return true;
  }

  // Set source enabled/disabled state
  function setSourceEnabled(url, enabled) {
    var newSources = [];
    var found = false;
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === url) {
        newSources.push({
                          name: root.pluginSources[i].name,
                          url: root.pluginSources[i].url,
                          enabled: enabled
                        });
        found = true;
      } else {
        newSources.push(root.pluginSources[i]);
      }
    }

    if (!found) {
      Logger.w("PluginRegistry", "Source not found:", url);
      return false;
    }

    root.pluginSources = newSources;
    save();
    Logger.i("PluginRegistry", "Source", url, enabled ? "enabled" : "disabled");
    return true;
  }

  // Check if source is enabled
  function isSourceEnabled(url) {
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].url === url) {
        return root.pluginSources[i].enabled !== false; // Default to true if not set
      }
    }
    return false;
  }

  // Get enabled sources only
  function getEnabledSources() {
    var enabledSources = [];
    for (var i = 0; i < root.pluginSources.length; i++) {
      if (root.pluginSources[i].enabled !== false) {
        enabledSources.push(root.pluginSources[i]);
      }
    }
    return enabledSources;
  }

  // Get plugin directory path
  function getPluginDir(pluginId) {
    return root.pluginsDir + "/" + pluginId;
  }

  // Get plugin settings file path
  function getPluginSettingsFile(pluginId) {
    return getPluginDir(pluginId) + "/settings.json";
  }

  // Validate manifest
  function validateManifest(manifest) {
    if (!manifest) {
      return {
        valid: false,
        error: "Manifest is null or undefined"
      };
    }

    var required = ["id", "name", "version", "author", "description"];
    for (var i = 0; i < required.length; i++) {
      if (!manifest[required[i]]) {
        return {
          valid: false,
          error: "Missing required field: " + required[i]
        };
      }
    }

    // TODO: rename "entryPoints" to "capabilities"
    if (!manifest.entryPoints) {
      return {
        valid: false,
        error: "Missing 'entryPoints' field"
      };
    }

    // Check version format (simple x.y.z check)
    var versionRegex = /^\d+\.\d+\.\d+$/;
    if (!versionRegex.test(manifest.version)) {
      return {
        valid: false,
        error: "Invalid version format (must be x.y.z)"
      };
    }

    return {
      valid: true,
      error: null
    };
  }
}
