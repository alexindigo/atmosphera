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

  readonly property int currentVersion: 4

  // The shell-shipped source has a CONSTANT identity ("builtin"), not a URL
  // hash — the payload path may move (it did: Plugins/ → builtin/plugins/)
  // and built-in plugin identity must never change when it does.
  readonly property string builtinSourceId: "builtin"
  readonly property string builtinSourceUrl: "file://" + Quickshell.shellDir + "/builtin/plugins"

  // Registry version as read from plugins.json at load (before any save
  // bumps it) — drives one-time content migrations
  property int _loadedVersion: 0

  Component.onCompleted: {
    ensurePluginsDirectory();
    bootstrap();
  }

  // Generate a short hash (6 characters) from a source URL
  function generateSourceHash(sourceUrl) {
    var hash = Crypto.sha256(sourceUrl);
    return hash.substring(0, 6);
  }

  // Generate composite key: plain ID for null/empty URLs, "builtin:id" for
  // the shell-shipped source, "hash:id" for everything else
  function generateCompositeKey(pluginId, sourceUrl) {
    if (!sourceUrl) {
      return pluginId;
    }
    if (sourceUrl === root.builtinSourceUrl) {
      return root.builtinSourceId + ":" + pluginId;
    }
    var hash = generateSourceHash(sourceUrl);
    return hash + ":" + pluginId;
  }

  // Parse composite key back to components
  function parseCompositeKey(compositeKey) {
    var colonIndex = compositeKey.indexOf(":");
    if (colonIndex !== -1) {
      var prefix = compositeKey.substring(0, colonIndex);
      if (prefix === root.builtinSourceId) {
        return {
          sourceHash: root.builtinSourceId,
          pluginId: compositeKey.substring(colonIndex + 1)
        };
      }
      if (colonIndex <= 6) {
        return {
          sourceHash: prefix,
          pluginId: compositeKey.substring(colonIndex + 1)
        };
      }
    }
    return {
      sourceHash: null,
      pluginId: compositeKey
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
    if (hash === root.builtinSourceId) {
      for (var i = 0; i < root.pluginSources.length; i++) {
        if (root.pluginSources[i].url === root.builtinSourceUrl) {
          return root.pluginSources[i].name;
        }
      }
      return "Built-in";
    }
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
      root._loadedVersion = adapter.version;

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

      root.migratePluginData(function () {
        scanPluginFolder();
      });
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
    Service.initialized;
  }

  // Icon set consolidation (v3): noctalia-icons-legacy merged into
  // atmosphera-icons. Bundled plugin copies in the user plugins dir are
  // shell-managed (not user data) and only ever copied on first run, so a
  // package upgrade leaves them stale — remove the legacy copy and refresh
  // the atmosphera-icons copy from the Built-in source. Runs once per user
  // (gated on the registry version read at load).
  function migrateIconSetsV3(done) {
    if (root._loadedVersion >= 3) {
      done();
      return;
    }

    // NOTE: this is intentionally the LEGACY pre-move payload path — the v3
    // migration matches keys hashed from the old URL. Do not "fix" it to
    // builtinSourceUrl.
    var builtinUrl = "file://" + Quickshell.shellDir + "/Plugins";
    var cmds = [];
    var statesChanged = false;

    for (var key in root.pluginStates) {
      var state = root.pluginStates[key];
      if (state.sourceUrl !== builtinUrl) {
        continue; // only touch Built-in source copies
      }
      var dir = root.pluginsDir + "/" + key;
      var dirEsc = dir.replace(/'/g, "'\\''");
      if (key.endsWith(":noctalia-icons-legacy")) {
        Logger.i("PluginRegistry", "v3 migration: removing retired icon set copy:", key);
        cmds.push("rm -rf '" + dirEsc + "'");
        delete root.pluginStates[key];
        statesChanged = true;
      } else if (key.endsWith(":atmosphera-icons")) {
        Logger.i("PluginRegistry", "v3 migration: refreshing atmosphera-icons from package");
        var src = Quickshell.shellDir + "/builtin/plugins/atmosphera-icons";
        var srcEsc = src.replace(/'/g, "'\\''");
        cmds.push("rm -rf '" + dirEsc + "' && mkdir -p '" + dirEsc + "' && cp -r '" + srcEsc + "/.' '" + dirEsc + "/'");
      }
    }

    if (cmds.length === 0) {
      done();
      return;
    }

    var migrateProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "${cmds.join(" && ").replace(/"/g, '\\"')}"]
      }
    `, root, "MigrateIconSetsV3");

    migrateProcess.exited.connect(function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("PluginRegistry", "v3 icon set migration failed (exit " + exitCode + ") — continuing with existing copies");
      }
      if (statesChanged) {
        root.save();
      }
      migrateProcess.destroy();
      done();
    });

    migrateProcess.running = true;
  }

  // v4: remap built-in plugin keys from the legacy URL-hash prefix
  // (hash of file://<shellDir>/Plugins) to the constant "builtin" source id.
  // Remaps plugins.json states, materialized dirs, per-plugin settings files,
  // and bar widget ids. Gated on _loadedVersion < 4.
  function migrateBuiltinKeysV4(done) {
    if (root._loadedVersion >= 4) {
      done();
      return;
    }

    var oldHash = generateSourceHash("file://" + Quickshell.shellDir + "/Plugins");
    var oldPrefix = oldHash + ":";
    var renames = [];
    var statesChanged = false;

    for (var key in root.pluginStates) {
      if (key.indexOf(oldPrefix) !== 0) {
        continue;
      }
      var suffix = key.substring(oldPrefix.length);
      var newKey = root.builtinSourceId + ":" + suffix;
      var state = root.pluginStates[key];
      state.sourceUrl = root.builtinSourceUrl;
      root.pluginStates[newKey] = state;
      delete root.pluginStates[key];
      statesChanged = true;
      renames.push({
                     "oldKey": key,
                     "newKey": newKey
                   });
    }

    if (renames.length === 0) {
      done();
      return;
    }
    Logger.i("PluginRegistry", "v4 migration: remapping", renames.length, "built-in plugin keys to 'builtin:'");

    // Bar widget ids embed the composite key ("plugin:<key>")
    function rewriteWidgetIds(widgets) {
      var changed = false;
      if (!widgets) {
        return false;
      }
      var sections = ["left", "center", "right"];
      for (var s = 0; s < sections.length; s++) {
        var list = widgets[sections[s]] || [];
        for (var i = 0; i < list.length; i++) {
          var id = list[i].id || "";
          for (var r = 0; r < renames.length; r++) {
            if (id === "plugin:" + renames[r].oldKey) {
              list[i].id = "plugin:" + renames[r].newKey;
              changed = true;
            }
          }
        }
      }
      return changed;
    }

    var widgetsChanged = rewriteWidgetIds(Settings.data.bar.widgets);
    var overrides = Settings.data.bar.screenOverrides || [];
    for (var o = 0; o < overrides.length; o++) {
      if (overrides[o] && overrides[o].widgets) {
        if (rewriteWidgetIds(overrides[o].widgets)) {
          Settings.setScreenOverride(overrides[o].name, "widgets", overrides[o].widgets);
        }
      }
    }
    if (widgetsChanged) {
      Settings.data.bar.widgets = Settings.data.bar.widgets;
    }

    // Filesystem: materialized dirs + per-plugin settings files
    var cmds = [];
    for (var i = 0; i < renames.length; i++) {
      var oldDir = (root.pluginsDir + "/" + renames[i].oldKey).replace(/'/g, "'\\''");
      var newDir = (root.pluginsDir + "/" + renames[i].newKey).replace(/'/g, "'\\''");
      cmds.push("if [ -e '" + oldDir + "' ]; then if [ -e '" + newDir + "' ]; then rm -rf '" + oldDir + "'; else mv '" + oldDir + "' '" + newDir + "'; fi; fi");

      var oldSettings = (Settings.configDir + "settings/plugins/" + renames[i].oldKey + ".json").replace(/'/g, "'\\''");
      var newSettings = (Settings.configDir + "settings/plugins/" + renames[i].newKey + ".json").replace(/'/g, "'\\''");
      cmds.push("if [ -e '" + oldSettings + "' ]; then if [ -e '" + newSettings + "' ]; then rm -f '" + oldSettings + "'; else mv '" + oldSettings + "' '" + newSettings + "'; fi; fi");
    }

    var migrateProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "${cmds.join(" && ").replace(/"/g, '\\"')}"]
      }
    `, root, "MigrateBuiltinKeysV4");

    migrateProcess.exited.connect(function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("PluginRegistry", "v4 key remap had filesystem errors (exit " + exitCode + ") — states were still remapped");
      }
      if (statesChanged) {
        root.save();
      }
      migrateProcess.destroy();
      done();
    });

    migrateProcess.running = true;
  }

  function migratePluginData(done) {
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

    root.migrateIconSetsV3(function () {
      root.migrateBuiltinKeysV4(done);
    });
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
  // and writes seeded plugins.json with composite keys (hash:id) for all bundled plugins.
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

      var sourceUrl = root.builtinSourceUrl;

      // Discover bundled plugins by scanning Plugins/ for manifests — no
      // hardcoded list; each plugin declares itself and its default state.
      var pluginsRoot = Quickshell.shellDir + "/builtin/plugins";
      var scanProc = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io
        Process {
          command: ["sh", "-c", "find '${pluginsRoot}' -mindepth 2 -maxdepth 2 -name manifest.json -type f"]
          stdout: StdioCollector {}
        }
      `, root, "ScanBundled");

      scanProc.exited.connect(function () {
        var out = (String(scanProc.stdout.text || "")).trim();
        scanProc.destroy();
        var paths = out ? out.split("\n") : [];
        root._readBundledManifests(paths, sourceUrl);
      });
      scanProc.running = true;

      probeProcess.destroy();
    });

    probeProcess.running = true;
  }

  // Read each bundled manifest.json (cat → JSON.parse), collecting
  // {dirName, id, defaultEnabled}, then materialize all in parallel.
  function _readBundledManifests(paths, sourceUrl) {
    var manifests = [];
    var pending = 0;

    if (paths.length === 0) {
      root._materializeBundled(manifests, sourceUrl);
      return;
    }

    for (var i = 0; i < paths.length; i++) {
      var manifestPath = paths[i];
      pending++;
      var catProc = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io
        Process {
          command: ["cat", "${manifestPath}"]
          stdout: StdioCollector {}
        }
      `, root, "ReadManifest_" + i);

      catProc.exited.connect((function (proc, path) {
        return function () {
          var text = String(proc.stdout.text || "");
          proc.destroy();
          try {
            var m = JSON.parse(text);
            if (m && m.id) {
              var dirName = path.split("/").slice(-2)[0];
              manifests.push({
                               "id": dirName,
                               "manifestId": m.id,
                               "defaultEnabled": (m.defaultEnabled === undefined) ? false : !!m.defaultEnabled
                             });
            }
          } catch (e) {
            Logger.w("PluginRegistry", "Malformed bundled manifest:", path, e);
          }
          pending--;
          if (pending === 0) {
            root._materializeBundled(manifests, sourceUrl);
          }
        };
      })(catProc, manifestPath));

      catProc.running = true;
    }
  }

  // Materialize each discovered plugin dir into the user plugins area,
  // then write the seed JSON with per-plugin default states.
  function _materializeBundled(manifests, sourceUrl) {
    var states = [];
    var pending = 0;

    if (manifests.length === 0) {
      root.writeSeedJson(sourceUrl, states);
      return;
    }

    for (var i = 0; i < manifests.length; i++) {
      var pluginId = manifests[i].id;
      var compositeKey = root.generateCompositeKey(pluginId, sourceUrl);
      var targetDir = root.pluginsDir + "/" + compositeKey;
      var srcDir = Quickshell.shellDir + "/builtin/plugins/" + pluginId;

      pending++;
      var copyProc = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io
        Process {
          command: ["sh", "-c", "test -d '${targetDir}' || mkdir -p '${targetDir}' && cp -r '${srcDir}/.' '${targetDir}/'"]
        }
      `, root, "CopyPlugin_" + pluginId);

      copyProc.exited.connect((function (proc, entry) {
        return function () {
          proc.destroy();
          states.push({
                        "id": entry.manifestId,
                        "enabled": entry.defaultEnabled
                      });
          pending--;
          if (pending === 0) {
            root.writeSeedJson(sourceUrl, states);
          }
        };
      })(copyProc, manifests[i]));

      copyProc.running = true;
    }
  }

  // Write seeded plugins.json with composite keys for bundled plugins.
  // Written via a process (not FileView) so write completion is deterministic:
  // the real FileView's path is only assigned once the seed is fully on disk.
  // Previously the temp FileView wrote asynchronously while the main FileView
  // immediately tried to load the same path — a race that left plugins.json
  // unread on first run, so the scanner defaulted all bundled plugins to
  // enabled:false and no sources were listed.
  // Note: seed JSON is ASCII-safe (hex hash, file:// URL, plain keys), so
  // Qt.btoa is safe here.
  function writeSeedJson(sourceUrl, states) {
    var seed = {
      "version": root.currentVersion,
      "sources": [
        {
          "enabled": true,
          "name": "Built-in",
          "url": sourceUrl
        },
        {
          "enabled": true,
          "name": "Atmosphera Plugins",
          "url": "https://github.com/alexindigo/atmosphera-plugins"
        },
        {
          "enabled": false,
          "name": "Atmosphera Wallpapers",
          "url": "https://github.com/atmosphera/atmosphera-wallpapers"
        }
      ],
      "states": ({})
    };
    for (var i = 0; i < states.length; i++) {
      seed.states[root.generateCompositeKey(states[i].id, sourceUrl)] = {
        "enabled": !!states[i].enabled,
        "sourceUrl": sourceUrl
      };
    }

    var b64 = Qt.btoa(JSON.stringify(seed));
    var writerProc = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "echo '${b64}' | base64 -d > '${root.pluginsFile}'"]
      }
    `, root, "SeedPluginsWriter");

    writerProc.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.i("PluginRegistry", "Seeded plugins.json with bundled defaults");
      } else {
        Logger.e("PluginRegistry", "Failed to write seed plugins.json, exit:", exitCode);
      }
      // Write outcome is final (success or failure) — safe to hand to FileView now.
      pluginsFileView.path = root.pluginsFile;
      writerProc.destroy();
    });
    writerProc.running = true;
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
    // Built-in plugins run from the source tree (shellDir/Plugins) — never
    // from a copied install in the config dir, which goes stale every time
    // the source changes (observed: shell rendering a weeks-old copy of a
    // built-in plugin while the source had moved on).
    var builtInUrl = root.builtinSourceUrl;
    var src = root.pluginStates[pluginId]?.sourceUrl || "";
    if (src === builtInUrl) {
      var parsed = root.parseCompositeKey(pluginId);
      return Quickshell.shellDir + "/builtin/plugins/" + parsed.pluginId;
    }
    return root.pluginsDir + "/" + pluginId;
  }

  // Get plugin settings file path (user-owned area: survives plugin
  // uninstall/reinstall, which wipes only the plugin's code dir)
  function getPluginSettingsFile(pluginId) {
    return Settings.configDir + "settings/plugins/" + pluginId + ".json";
  }

  // Legacy per-plugin settings location (inside the plugin dir); read-only
  // fallback for users upgrading from before the path move.
  function getLegacyPluginSettingsFile(pluginId) {
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
