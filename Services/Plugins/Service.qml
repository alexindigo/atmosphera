pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/OwnedProcess.js" as OwnedProcess
import "../../Helpers/SettingsListCommands.js" as Lists
import "PluginSettingsRead.js" as SettingsRead
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services
import qs.Services.Plugins
import qs.Services.UI

Singleton {
  id: root

  signal pluginLoaded(string pluginId)
  signal pluginUnloaded(string pluginId)
  signal pluginEnabled(string pluginId)
  signal pluginDisabled(string pluginId)
  signal pluginReloaded(string pluginId)
  signal availablePluginsUpdated
  signal allPluginsLoaded
  signal pluginSettingsCompleted(string pluginId, var result)

  property var _settingsOwners: Object.create(null)
  property var _pluginEntries: Object.create(null)
  property var _retiringPlugins: Object.create(null)
  property var _pluginLoads: Object.create(null)
  property var _pluginLoadGenerations: Object.create(null)
  property var _pluginSaveFailures: []
  property var _pluginSaveStores: []
  property int _pluginSaveSequence: 0
  property var _pluginReplacements: Object.create(null)

  // Entry points outlive registry removal and destroy() returns. Keep their
  // preference APIs until the actual QObject destruction stacks have unwound.
  function retainPluginEntry(item) {
    if (!item || !("pluginApi" in item) || !item.pluginApi)
      return;
    root.retainPluginConsumer(item, item.pluginApi);
  }
  function retainPluginConsumer(item, api) {
    while (api && "base" in api)
      api = api.base;
    if (!api || !("settingsOwner" in api) || !api.settingsOwner || api.settingsOwner.closed)
      return;
    var key = api.pluginId;
    var entries = _pluginEntries[key] || [];
    if (entries.some(function (entry) {
      return entry.item === item;
    }))
      return;
    var entry = {
      item: item,
      api: api
    };
    entries.push(entry);
    _pluginEntries[key] = entries;
    item.Component.destruction.connect(function () {
      // Component.destruction precedes child destruction and other attached
      // handlers. The queued release observes the end of that whole stack.
      Qt.callLater(function () {
        var current = root._pluginEntries[key] || [];
        root._pluginEntries[key] = current.filter(function (candidate) {
          return candidate !== entry;
        });
        root._settlePluginUnload(key);
      });
    });
  }

  // One requested-save lifetime for shared and placement APIs. Waiting here
  // never flushes manual edits that the plugin did not ask to publish.
  function savePluginSettings(api, handle, callback) {
    var base = api;
    while (base && "base" in base)
      base = base.base;
    if (!handle || !api.settingsReady || !base || !base.settingsOwner || base.settingsOwner.closed || base.settingsOwner.status !== "Ready") {
      var code = "base" in api && api.settingsError === "overlay-identity" ? "overlay-identity" : "plugin-owner";
      Qt.callLater(function () {
        if (typeof callback === "function")
          callback({
                     status: "failed",
                     error: {
                       code: code
                     }
                   });
      });
      return false;
    }
    var selected = "base" in api ? PluginInstances.address(api.placement) : null;
    if ("base" in api && !selected) {
      Qt.callLater(function () {
        if (typeof callback === "function")
          callback({
                     status: "failed",
                     error: {
                       code: "overlay-identity"
                     }
                   });
      });
      return false;
    }
    var store = selected ? Settings.store : base.settingsOwner.store;
    var paths = selected ? [selected.path] : [["settings"]];
    return root._savePluginSelection(api, store, paths, callback);
  }
  function _savePluginSelection(api, store, paths, callback) {
    if (!root._pluginSaveStores.some(function (entry) {
      return entry === store;
    })) {
      root._pluginSaveStores = root._pluginSaveStores.filter(function (entry) {
        return entry !== null;
      }).concat([store]);
      store.completed.connect(function (result) {
        root._observePluginSaveCoverage(store, result);
      });
    }
    var sequence = ++root._pluginSaveSequence;
    api._pendingSettingsSaves++;
    return store.saveSelected(paths, function (result) {
      var confirmed = result.coveredRevisions || {};
      var coverage = result.coverage || [];
      // Confirmed coverage from a newer requested save supersedes an older
      // failure on those keys, even when that later receipt is partial.
      var successes = coverage.filter(function (entry) {
        return Object.prototype.hasOwnProperty.call(confirmed, entry.sourceId);
      });
      root._pluginSaveFailures = root._pluginSaveFailures.filter(function (failure) {
        if (failure.store !== store || failure.sequence > sequence)
          return true;
        if (!failure.paths.length)
          return result.status === "failed" || JSON.stringify(failure.selection) !== JSON.stringify(paths);
        failure.paths = failure.paths.filter(function (path) {
          if (successes.some(function (entry) {
            return JSON.stringify(entry.path) === JSON.stringify(path);
          }))
            return false;
          // A successful bounded request also proves there is no earlier
          // eligible work left in its selection (nothing_to_save included).
          return result.status === "failed" || !paths.some(function (selected) {
            return selected.length <= path.length && selected.every(function (part, index) {
              return part === path[index];
            });
          });
        });
        return failure.paths.length > 0;
      });
      if (result.status === "failed") {
        var failedPaths = coverage.filter(function (entry) {
          return !Object.prototype.hasOwnProperty.call(confirmed, entry.sourceId);
        }).map(function (entry) {
          return entry.path.slice();
        });
        root._pluginSaveFailures.push({
                                        api: api,
                                        store: store,
                                        sequence: sequence,
                                        paths: failedPaths,
                                        selection: paths,
                                        result: result
                                      });
      }
      api._lastSettingsSave = result;
      try {
        root.pluginSettingsCompleted(api.pluginId, result);
        if (typeof callback === "function")
          callback(result);
      } finally {
        api._pendingSettingsSaves--;
        root._completePluginSaves(api);
      }
    });
  }
  function _observePluginSaveCoverage(store, result) {
    var confirmed = result.coveredRevisions || {};
    var covered = (result.coverage || []).filter(function (entry) {
      return Object.prototype.hasOwnProperty.call(confirmed, entry.sourceId);
    });
    if (!covered.length)
      return;
    // All successful writers on the native owner supersede older failed
    // coverage, not only another call through this API (dialogs/autosave too).
    root._pluginSaveFailures = root._pluginSaveFailures.filter(function (failure) {
      if (failure.store !== store || !failure.paths.length)
        return true;
      failure.paths = failure.paths.filter(function (path) {
        return !covered.some(function (entry) {
          return JSON.stringify(entry.path) === JSON.stringify(path);
        });
      });
      return failure.paths.length > 0;
    });
  }
  function _completePluginSaves(api) {
    if (api._pendingSettingsSaves)
      return;
    var waiters = api._settingsSaveWaiters;
    api._settingsSaveWaiters = [];
    var failure = root._pluginSaveFailures.find(function (entry) {
      return entry.api === api;
    });
    var result = failure ? failure.result : (api._lastSettingsSave && api._lastSettingsSave.status !== "failed" ? api._lastSettingsSave : {
                                                                                                                    status: "nothing_to_save"
                                                                                                                  });
    waiters.forEach(function (callback) {
      callback(result);
    });
  }
  function waitForPluginSaves(api, callback, retry) {
    if (retry && !api._pendingSettingsSaves) {
      var failures = root._pluginSaveFailures.filter(function (entry) {
        return entry.api === api;
      });
      var first = failures[0];
      if (first && first.paths.length) {
        var paths = [];
        failures.forEach(function (failure) {
          failure.paths.forEach(function (path) {
            if (!paths.some(function (selected) {
              return JSON.stringify(selected) === JSON.stringify(path);
            }))
              paths.push(path.slice());
          });
        });
        root._savePluginSelection(api, first.store, paths, function () {
          root.waitForPluginSaves(api, callback, false);
        });
        return;
      }
    }
    api._settingsSaveWaiters.push(callback);
    Qt.callLater(function () {
      root._completePluginSaves(api);
    });
  }
  function retainPluginEditor(editor, api) {
    root.retainPluginConsumer(editor, api);
    var base = api;
    while (base && "base" in base)
      base = base.base;
    var key = base.pluginId;
    editor.ownerCurrent = function () {
      return base !== null && root.getPluginAPI(key) === base;
    };
    // Factory-created editors close on discard; declarative test consumers
    // keep their ordinary parent-owned lifetime.
    editor.closedChanged.connect(function () {
      if (editor.closed)
        editor.destroy();
    });
  }

  function _settlePluginUnload(pluginId) {
    var retirement = _retiringPlugins[pluginId];
    if (!retirement || !retirement.notified || retirement.settling || (_pluginEntries[pluginId] || []).length)
      return;
    retirement.settling = true;
    var retry = retirement.retry === true;
    retirement.retry = false;
    function finish(result) {
      retirement.settling = false;
      retirement.failed = result.status === "failed";
      if (result.status !== "failed") {
        if (retirement.owner) {
          if (root._settingsOwners[pluginId] === retirement.owner)
            delete root._settingsOwners[pluginId];
          retirement.owner.detach();
          retirement.owner.destroy();
        }
        delete root._retiringPlugins[pluginId];
        delete root._pluginEntries[pluginId];
      } else {
        // Keep failed requested work and its APIs available for explicit Retry.
        root.recordPluginError(pluginId, "settings", "Final plugin settings save failed; preferences retained");
      }
      var callbacks = retirement.callbacks;
      retirement.callbacks = [];
      callbacks.forEach(function (callback) {
        callback(result);
      });
    }
    PluginInstances.settlePlugin(pluginId, function (result) {
      if (result.status === "failed") {
        finish(result);
        return;
      }
      if (retirement.api)
        root.waitForPluginSaves(retirement.api, finish, retry);
      else
        finish({
                 status: "nothing_to_save"
               });
    }, retry);
  }

  Component {
    id: preferenceOwnerFactory
    PluginPreferenceOwner {}
  }
  Component {
    id: preferenceEditorFactory
    PluginPreferenceEditor {}
  }

  // External profile IO must settle the actual owners, not serialize their
  // GUI values. Captured owner identities also fence plugin load/unload.
  function synchronizePreferences(operation, callback) {
    function readyOwners() {
      return Object.keys(root._settingsOwners).sort().filter(function (key) {
        var owner = root._settingsOwners[key];
        return owner && !owner.closed && owner.status === "Ready";
      }).map(function (key) {
        return {
          key: key,
          owner: root._settingsOwners[key]
        };
      });
    }
    var owners = readyOwners();
    function unchanged() {
      var currentOwners = readyOwners();
      return currentOwners.length === owners.length && owners.every(function (entry, index) {
        return currentOwners[index].key === entry.key && currentOwners[index].owner === entry.owner;
      });
    }
    function failed(code) {
      callback({
                 status: "failed",
                 refreshState: "not_refreshed",
                 error: {
                   code: code
                 }
               });
    }
    var fences = [];
    function current() {
      return unchanged() && fences.every(function (fence) {
        return fence.paths.every(function (path, index) {
          return fence.store.info(path).latestInput === fence.inputs[index];
        });
      });
    }
    function greater(a, b) {
      return a.length > b.length || (a.length === b.length && a > b);
    }
    function next(index) {
      if (!unchanged()) {
        failed("profile-owner-changed");
        return;
      }
      if (index > owners.length) {
        if (!current()) {
          failed("profile-concurrent-edit");
          return;
        }
        callback({
                   status: "current",
                   refreshState: "current",
                   isCurrent: current
                 });
        return;
      }
      var store = index === 0 ? Settings.store : owners[index - 1].owner.store;
      var paths = index === 0 ? store.inputPaths : store.settingsKeys.map(function (key) {
        return ["settings", key];
      });
      store[operation](function (result) {
        // Plain store save/reload receipts do not carry editor refreshState.
        // Their settled owner and unresolved-group facts fence this workflow.
        if (["saved", "nothing_to_save", "reloaded"].indexOf(result.status) === -1 || (result.unresolvedGroups && result.unresolvedGroups.length)) {
          var ownerKey = index === 0 ? "shell" : owners[index - 1].key;
          var blockers = (result.unresolvedGroups || []).map(function (token) {
            var info = store.groupInfo(token);
            return {
              ownerKey: ownerKey,
              groupToken: token,
              requestKey: info.requestKey || "",
              state: info.state || "unresolved"
            };
          });
          callback(Object.assign({}, result, {
                                   preferenceOwnerKey: ownerKey,
                                   preferenceBlockers: blockers
                                 }));
          return;
        }
        var inputs = paths.map(function (path) {
          return store.info(path).latestInput;
        });
        if (inputs.some(function (input) {
          return greater(input, result.inputPrefix);
        })) {
          failed("profile-concurrent-edit");
          return;
        }
        fences.push({
                      store: store,
                      paths: paths,
                      inputs: inputs
                    });
        next(index + 1);
      });
    }
    Qt.callLater(function () {
      if (["save", "reload"].indexOf(operation) === -1) {
        failed("profile-operation");
        return;
      }
      next(0);
    });
  }

  function _openSettingsOwner(pluginId, callback) {
    if (_retiringPlugins[pluginId]) {
      _retiringPlugins[pluginId].callbacks.push(function (result) {
        if (result.status === "failed")
          callback(null);
        else
          root._openSettingsOwner(pluginId, callback);
      });
      root._settlePluginUnload(pluginId);
      return;
    }
    var owner = _settingsOwners[pluginId];
    if (!owner) {
      owner = preferenceOwnerFactory.createObject(root, {
                                                    pluginId: pluginId,
                                                    pluginDirectory: Registry.getPluginDir(pluginId),
                                                    userFile: Registry.getPluginSettingsFile(pluginId),
                                                    configFile: Settings.configDir + "settings/plugins/" + pluginId + ".config.json",
                                                    cacheDirectory: Settings.cacheDir + "plugin-schemas",
                                                    evidenceDirectory: Settings.cacheDir + "plugin-settings-conflicts"
                                                  });
      _settingsOwners[pluginId] = owner;
      owner.completed.connect(function (result) {
        if (["save", "apply", "flush", "close"].indexOf(result.operation) !== -1)
          root.pluginSettingsCompleted(pluginId, result);
      });
    }
    var delivered = false;
    function settled() {
      if (delivered || owner.status === "Loading")
        return;
      delivered = true;
      owner.settled.disconnect(settled);
      var ready = !owner.closed && owner.status === "Ready";
      if (!ready && root._settingsOwners[pluginId] === owner) {
        delete root._settingsOwners[pluginId];
        if (!owner.closed)
          owner.detach();
        owner.destroy();
      }
      callback(ready ? owner : null);
    }
    owner.settled.connect(settled);
    Qt.callLater(settled);
  }

  // Keep the callback-shaped reader on the same native owner as runtime APIs.
  // This returns its namespace, never a second mutable preferences snapshot.
  function loadPluginSettings(pluginId, callback) {
    root._openSettingsOwner(pluginId, function (owner) {
      if (typeof callback === "function")
        callback(owner ? owner.settingsScope.values : null);
    });
  }

  // When available plugins are updated, check if we should perform update check
  onAvailablePluginsUpdated: {
    if (shouldCheckUpdatesAfterFetch && Object.keys(activeFetches).length === 0) {
      Logger.d("PluginService", "All registry fetches complete, performing update check");
      performUpdateCheck();
    }
  }

  // Loaded plugin instances
  property var loadedPlugins: ({}) // { pluginId: { component, instance, api } }

  // Available plugins from all sources (fetched from registries)
  property var availablePlugins: ([]) // Array of plugin metadata from all sources

  // Plugin updates available: { pluginId: { currentVersion, availableVersion } }
  property var pluginUpdates: ({})

  // Plugin updates that require a newer Noctalia version: { pluginId: { currentVersion, availableVersion, minNoctaliaVersion } }
  property var pluginUpdatesPending: ({})

  // Plugin load errors: { pluginId: { error: string, entryPoint: string, timestamp: date } }
  property var pluginErrors: ({})
  signal pluginLoadError(string pluginId, string entryPoint, string error)

  // Track currently installing plugins: { pluginId: true }
  property var installingPlugins: ({})

  // Hot reload: file watchers for plugin directories
  property var pluginFileWatchers: ({}) // { pluginId: FileView }
  property list<string> pluginHotReloadEnabled: [] // List of pluginIds that have hot reload enabled

  // Track active fetches
  property var activeFetches: ({})

  property bool initialized: false
  property bool pluginsFullyLoaded: false

  // Plugin container from shell.qml (for placing Main instances in graphics scene)
  property var pluginContainer: null

  // Screen detector from shell.qml (for withCurrentScreen in plugin API)
  property var screenDetector: null

  // Track if we need to initialize once container is ready
  property bool needsInit: false

  // Watch for pluginContainer to be set
  onPluginContainerChanged: {
    if (root.pluginContainer && root.needsInit) {
      Logger.d("PluginService", "Plugin container now available, initializing plugins");
      root.needsInit = false;
      root.init();
    }
  }

  // Listen for PluginRegistry to finish loading
  Connections {
    target: Registry

    function onPluginsChanged() {
      if (!root.initialized) {
        if (root.pluginContainer) {
          // Container already available, init now
          root.init();
        } else {
          // Container not ready, wait for it
          Logger.d("PluginService", "Deferring plugin init until container is ready");
          root.needsInit = true;
        }
      }
    }
  }

  // When debug mode is disabled, tear down all hot reload watchers
  Connections {
    target: Settings

    function onIsDebugChanged() {
      if (!Settings.isDebug && root.pluginHotReloadEnabled.length > 0) {
        Logger.i("PluginService", "Debug mode disabled, removing all hot reload watchers");
        // Remove watchers for all hot-reload-enabled plugins
        var plugins = root.pluginHotReloadEnabled.slice(); // copy since we mutate
        for (var i = 0; i < plugins.length; i++) {
          removePluginFileWatcher(plugins[i]);
        }
        root.pluginHotReloadEnabled = [];
      }
    }
  }

  // Listen for language changes to reload plugin translations
  Connections {
    target: I18n

    function onLanguageChanged() {
      Logger.d("PluginService", "Language changed to:", I18n.langCode, "- reloading plugin translations");

      // Reload translations for all loaded plugins
      for (var pluginId in root.loadedPlugins) {
        // Use IIFE to capture current loop values (avoid closure bug)
        (function (id, plugin) {
          if (plugin && plugin.api && plugin.manifest) {
            // Update current language
            plugin.api.currentLanguage = I18n.langCode;

            // Reload translations
            loadPluginTranslationsAsync(id, plugin.manifest, I18n.langCode, function (translations) {
              plugin.api.pluginTranslations = translations;

              // Reload English fallback for non-English languages
              if (I18n.langCode !== "en") {
                loadPluginTranslationsAsync(id, plugin.manifest, "en", function (fallbackTranslations) {
                  plugin.api.pluginFallbackTranslations = fallbackTranslations;
                  plugin.api.translationVersion++;
                  Logger.d("PluginService", "Reloaded translations for plugin:", id);
                });
              } else {
                plugin.api.pluginFallbackTranslations = {};
                plugin.api.translationVersion++;
                Logger.d("PluginService", "Reloaded translations for plugin:", id);
              }
            });
          }
        })(pluginId, root.loadedPlugins[pluginId]);
      }

      // Update translation file watchers to watch the new language's files
      if (root.pluginHotReloadEnabled.length > 0) {
        updateTranslationWatchers();
      }
    }
  }

  // Track pending plugin loads for init completion
  property int _pendingPluginLoads: 0

  function init() {
    if (root.initialized) {
      Logger.d("PluginService", "Already initialized, skipping");
      return;
    }

    Logger.i("PluginService", "Initializing plugin system");
    root.initialized = true;

    // Debug: Check what's in PluginRegistry
    var allInstalled = Registry.getAllInstalledPluginIds();
    Logger.d("PluginService", "All installed plugins:", JSON.stringify(allInstalled));
    Logger.d("PluginService", "Plugin states:", JSON.stringify(Registry.pluginStates));

    // Load all enabled plugins
    var enabledIds = Registry.getEnabledPluginIds();
    Logger.i("PluginService", "Found", enabledIds.length, "enabled plugins:", JSON.stringify(enabledIds));

    // Count plugins that need to be loaded
    var pluginsToLoad = [];
    for (var i = 0; i < enabledIds.length; i++) {
      var manifest = Registry.getPluginManifest(enabledIds[i]);
      if (manifest) {
        pluginsToLoad.push(enabledIds[i]);
      } else {
        Logger.w("PluginService", "Plugin", enabledIds[i], "is enabled but not found on disk - install");
        var sourceUrl = Registry.getPluginSourceUrl(enabledIds[i]);
        root.installPlugin({
                             id: enabledIds[i],
                             source: {
                               url: sourceUrl
                             }
                           }, false, function (success, error, registeredKey) {
                             if (success) {
                               ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-success", {
                                                                                                  "plugin": registeredKey
                                                                                                }));
                               // Load the plugin since it was already enabled (state persisted but files were missing)
                               loadPlugin(registeredKey, function () {
                                 root.addWidgetToBar("plugin:" + registeredKey, "right");
                               });
                             } else {
                               ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-error", {
                                                                                                 "error": error || "Unknown error"
                                                                                               }));
                             }
                           });
      }
    }

    // If no plugins to load, mark as complete immediately
    if (pluginsToLoad.length === 0) {
      root.pluginsFullyLoaded = true;
      Logger.i("PluginService", "No plugins to load");
      root.allPluginsLoaded();
      root._isStartupCheck = true;
      refreshAvailablePlugins();
      return;
    }

    // Track pending loads
    root._pendingPluginLoads = pluginsToLoad.length;

    // Load all plugins (async - they will call _onPluginLoadComplete when done)
    for (var j = 0; j < pluginsToLoad.length; j++) {
      Logger.d("PluginService", "Attempting to load plugin:", pluginsToLoad[j]);
      loadPlugin(pluginsToLoad[j], null, null, true);
    }
  }

  // Called when a plugin finishes loading (success or failure)
  function _onPluginLoadComplete() {
    if (root._pendingPluginLoads <= 0)
      return;
    root._pendingPluginLoads--;

    if (root._pendingPluginLoads <= 0) {
      // All plugins finished loading
      root.pluginsFullyLoaded = true;
      Logger.i("PluginService", "All plugins loaded");
      root.allPluginsLoaded();

      // Fetch available plugins from all sources
      root._isStartupCheck = true;
      refreshAvailablePlugins();
    }
  }

  // Refresh available plugins from all sources
  function refreshAvailablePlugins() {
    // If fetches are already in progress, don't start new ones
    if (Object.keys(activeFetches).length > 0) {
      Logger.d("PluginService", "Refresh already in progress, skipping duplicate refresh");
      return;
    }

    Logger.i("PluginService", "Refreshing available plugins");
    root.availablePlugins = [];

    // Signal that we want to check for updates after refresh completes
    shouldCheckUpdatesAfterFetch = true;

    var enabledSources = Registry.getEnabledSources();
    Logger.d("PluginService", "Fetching from", enabledSources.length, "enabled sources");
    for (var i = 0; i < enabledSources.length; i++) {
      fetchPluginRegistry(enabledSources[i]);
    }
  }

  // Fetch plugin registry from a source using git sparse-checkout
  function fetchPluginRegistry(source) {
    var repoUrl = source.url;

    Logger.d("PluginService", "Fetching registry from:", repoUrl);

    var fetchCmd;
    if (repoUrl.startsWith("file://")) {
      // Local directory source: read the catalog directly. The directory may
      // not be a git repo (e.g. the Built-in shellDir/Plugins source), and
      // even when it is, the checked-out working tree is what we want.
      var localPath = repoUrl.substring(7);
      fetchCmd = "cat '" + localPath + "/registry.json' 2>/dev/null";
    } else {
      // Use git sparse-checkout to fetch only registry.json (--no-cone for single file)
      // GIT_TERMINAL_PROMPT=0 prevents hanging on private repos that need auth
      fetchCmd = "temp_dir=$(mktemp -d) && GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --sparse --depth=1 --quiet '" + repoUrl + "' \"$temp_dir\" 2>/dev/null && cd \"$temp_dir\" && git sparse-checkout set --no-cone /registry.json 2>/dev/null && cat \"$temp_dir/registry.json\"; rm -rf \"$temp_dir\"";
    }

    var fetchProcess = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["sh", "-c", "' + fetchCmd.replace(/"/g, '\\"') + '"]; stdout: StdioCollector {} }', root, "FetchRegistry_" + Date.now());

    activeFetches[source.url] = fetchProcess;

    fetchProcess.stdout.onStreamFinished.connect(function () {
      var response = fetchProcess.stdout.text;

      // Debug: log the raw response
      Logger.d("PluginService", "Registry response length:", response ? response.length : 0);

      if (!response || response.trim() === "") {
        Logger.e("PluginService", "Empty response from", source.name);
        delete activeFetches[source.url];
        fetchProcess.destroy();
        return;
      }

      try {
        var registry = JSON.parse(response);

        if (registry && registry.plugins && Array.isArray(registry.plugins)) {
          // Add source info to each plugin
          for (var i = 0; i < registry.plugins.length; i++) {
            var plugin = registry.plugins[i];
            plugin.source = source;

            // Check if already downloaded - use composite key
            var compositeKey = Registry.generateCompositeKey(plugin.id, source.url);
            plugin.downloaded = Registry.isPluginDownloaded(compositeKey);
            plugin.enabled = Registry.isPluginEnabled(compositeKey);

            root.availablePlugins.push(plugin);
          }

          Logger.i("PluginService", `Parsed ${registry.plugins.length} plugins manifest from '${source.name}'`);

          // Remove from active fetches BEFORE emitting signal so handler sees correct count
          delete activeFetches[source.url];
          fetchProcess.destroy();

          root.availablePluginsUpdated();
          return;
        }
      } catch (e) {
        Logger.e("PluginService", "Failed to parse registry from", source.name, ":", e);
        Logger.e("PluginService", "Response was:", response ? response.substring(0, 200) : "null");
      }

      // Clean up on error or empty response
      delete activeFetches[source.url];
      fetchProcess.destroy();
    });

    fetchProcess.exited.connect(function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("PluginService", "Failed to fetch registry from", source.name, "- exit code:", exitCode);
        delete activeFetches[source.url];
        fetchProcess.destroy();
      }
    });

    fetchProcess.running = true;
  }

  // Check for plugin ID collision before installation
  function checkPluginCollision(pluginMetadata) {
    var sourceUrl = pluginMetadata.source.url;
    var compositeKey = Registry.generateCompositeKey(pluginMetadata.id, sourceUrl);

    // Check if this exact composite key already exists
    if (Registry.isPluginDownloaded(compositeKey)) {
      return {
        collision: true,
        reason: "already_installed",
        existingKey: compositeKey,
        message: I18n.tr("panels.plugins.collision-already-installed")
      };
    }

    // For official plugins, also check if any custom version with same base ID exists
    if (Registry.isMainSource(sourceUrl)) {
      var allInstalled = Registry.getAllInstalledPluginIds();
      for (var i = 0; i < allInstalled.length; i++) {
        var parsed = Registry.parseCompositeKey(allInstalled[i]);
        if (parsed.pluginId === pluginMetadata.id && !parsed.isOfficial) {
          var sourceName = Registry.getSourceNameByHash(parsed.sourceHash) || I18n.tr("panels.plugins.source-custom");
          return {
            collision: true,
            reason: "custom_version_exists",
            existingKey: allInstalled[i],
            message: I18n.tr("panels.plugins.collision-custom-version-exists", {
                               source: sourceName
                             })
          };
        }
      }
    }

    // For custom plugins, check if official version exists
    if (!Registry.isMainSource(sourceUrl)) {
      if (Registry.isPluginDownloaded(pluginMetadata.id)) {
        return {
          collision: true,
          reason: "official_version_exists",
          existingKey: pluginMetadata.id,
          message: I18n.tr("panels.plugins.collision-official-version-exists")
        };
      }
    }

    return {
      collision: false
    };
  }

  // Download and install a plugin using git sparse-checkout
  // skipCollisionCheck: set to true when updating an existing plugin
  // SINGLE SOURCE OF TRUTH for plugin version compatibility. Two tracks:
  //   Atmosphera-native → minAtmospheraVersion vs the real fork version
  //   Noctalia/upstream → major(minNoctaliaVersion) <= noctaliaCompatMajor
  // installPlugin() and performUpdateCheck() MUST both route through this. They
  // previously held duplicate copies, and a refactor updated one and broke the other.
  function checkPluginCompatibility(metadata) {
    var minAtmo = metadata.minAtmospheraVersion;
    if (minAtmo) {
      if (!Version.versionKnown) {
        Logger.w("PluginService", "Shell version unknown — skipping minAtmospheraVersion gate for", metadata.id || metadata.name);
      } else if (Version.compareVersions(minAtmo, Version.currentVersion) > 0) {
        return {
          compatible: false,
          track: "atmosphera",
          requiredVersion: minAtmo
        };
      }
    }

    var minNoct = metadata.minNoctaliaVersion;
    if (minNoct) {
      var parts = Version.parseVersionParts(minNoct);
      if (parts.length === 0) {
        Logger.w("PluginService", "Unparseable minNoctaliaVersion", minNoct, "— treating as compatible");
      } else if (parts[0] > Version.noctaliaCompatMajor) {
        return {
          compatible: false,
          track: "noctalia",
          requiredVersion: minNoct
        };
      }
    }

    return {
      compatible: true,
      track: "",
      requiredVersion: ""
    };
  }

  function installPlugin(pluginMetadata, skipCollisionCheck, callback) {
    var pluginId = pluginMetadata.id;
    // Do not include hash for 3rd party plugins
    var pluginIdRegex = /^[a-f0-9]{6}:/;
    if (pluginIdRegex.test(pluginId)) {
      pluginId = pluginId.substring(7);
    }

    var source = pluginMetadata.source;

    // Check for collision first (skip when updating)
    if (!skipCollisionCheck) {
      var collision = checkPluginCollision(pluginMetadata);
      if (collision.collision) {
        Logger.w("PluginService", "Plugin collision detected:", collision.message);
        ToastService.showError(I18n.tr("panels.plugins.title"), collision.message);
        if (callback)
          callback(false, collision.message);
        return;
      }

      // Version compatibility checks (skip when updating - that's handled in performUpdateCheck).
      // Single gate at checkPluginCompatibility(); message selected by track.
      var compat = root.checkPluginCompatibility(pluginMetadata);
      if (!compat.compatible) {
        var msg = (compat.track === "noctalia") ? I18n.tr("panels.plugins.install-incompatible-noctalia", {
                                                            "plugin": pluginMetadata.name,
                                                            "version": compat.requiredVersion
                                                          }) : I18n.tr("panels.plugins.install-incompatible", {
                                                                         "plugin": pluginMetadata.name,
                                                                         "version": compat.requiredVersion
                                                                       });
        Logger.w("PluginService", "Plugin incompatible (" + (compat.track || "unknown") + "):", msg);
        if (callback)
          callback(false, msg);
        return;
      }
    }

    // Generate composite key for the plugin folder
    var compositeKey = Registry.generateCompositeKey(pluginId, source.url);
    Logger.i("PluginService", "Installing plugin:", compositeKey, "from", source.name);

    var pluginDir = Registry.getPluginDir(compositeKey);
    var repoUrl = source.url;

    var downloadCmd;
    if (repoUrl.startsWith("file://")) {
      // Local source: copy directly without git
      var srcBase = repoUrl.substring(7);
      downloadCmd = "mkdir -p '" + pluginDir + "' && cp -r '" + srcBase + "/" + pluginId + "/.' '" + pluginDir + "/'";
    } else {
      // Use git sparse-checkout to clone only the plugin subfolder
      // GIT_TERMINAL_PROMPT=0 prevents hanging on private repos that need auth
      // Note: We download from the original pluginId folder in the repo, but save to compositeKey folder
      downloadCmd = "temp_dir=$(mktemp -d) && GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --sparse --depth=1 --quiet '" + repoUrl + "' \"$temp_dir\" 2>/dev/null && cd \"$temp_dir\" && git sparse-checkout set '" + pluginId + "' 2>/dev/null && mkdir -p '" + pluginDir + "' && rm -f \"$temp_dir/" + pluginId + "/settings.json\" && cp -r \"$temp_dir/" + pluginId
          + "/.\" '" + pluginDir + "/'; exit_code=$?; rm -rf \"$temp_dir\"; exit $exit_code";
    }

    // Mark as installing
    var newInstalling = Object.assign({}, root.installingPlugins);
    newInstalling[pluginId] = true;
    root.installingPlugins = newInstalling;

    var downloadProcess = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["sh", "-c", "' + downloadCmd.replace(/"/g, '\\"') + '"] }', root, "DownloadPlugin_" + pluginId);

    downloadProcess.exited.connect(function (exitCode) {
      // Mark as finished (remove from installing)
      var currentInstalling = Object.assign({}, root.installingPlugins);
      delete currentInstalling[pluginId];
      root.installingPlugins = currentInstalling;

      if (exitCode === 0) {
        Logger.i("PluginService", "Downloaded plugin:", compositeKey);

        // Load and validate manifest
        var manifestPath = pluginDir + "/manifest.json";
        loadManifest(manifestPath, function (success, manifest) {
          if (success) {
            var validation = Registry.validateManifest(manifest);
            if (validation.valid) {
              // Register plugin with source URL
              var registeredKey = Registry.registerPlugin(manifest, source.url);
              Logger.i("PluginService", "Installed plugin:", registeredKey);

              // Update available plugins list
              updatePluginInAvailable(pluginId, {
                                        downloaded: true
                                      });

              if (callback)
                callback(true, null, registeredKey);
            } else {
              Logger.e("PluginService", "Invalid manifest:", validation.error);
              if (callback)
                callback(false, "Invalid manifest: " + validation.error);
            }
          } else {
            Logger.e("PluginService", "Failed to load manifest for:", compositeKey);
            if (callback)
              callback(false, "Failed to load manifest");
          }
        });
      } else {
        Logger.e("PluginService", "Failed to download plugin:", compositeKey);
        if (callback)
          callback(false, "Download failed");
      }

      downloadProcess.destroy();
    });

    downloadProcess.running = true;
  }

  // Uninstall a plugin (compositeKey is the full key like "abc123:my-plugin" or plain "my-plugin")
  function uninstallPlugin(compositeKey, callback) {
    Logger.i("PluginService", "Uninstalling plugin:", compositeKey);
    root.unloadPlugin(compositeKey, true, function (result) {
      if (result.status === "failed") {
        if (typeof callback === "function")
          callback(false, result.error?.code || "Final plugin settings save failed");
        return;
      }
      root._removeRetiredPlugin(compositeKey, callback);
    });
  }

  function _removeRetiredPlugin(compositeKey, callback) {
    // File removal, like update installation, starts only after retirement.
    if (Registry.isPluginEnabled(compositeKey)) {
      disablePlugin(compositeKey);
    }

    // Uninstall removes the user-owned copy — never the load path returned by
    // getPluginDir(), which for built-in-sourced plugins is the root-owned
    // source tree (shellDir/Plugins) and must never be deleted.
    var pluginDir = Registry.pluginsDir + "/" + compositeKey;

    var removeProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "rm -rf '${pluginDir}'"]
      }
    `, root, "RemovePlugin_" + compositeKey);

    removeProcess.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Registry.unregisterPlugin(compositeKey);
        Logger.i("PluginService", "Uninstalled plugin:", compositeKey);

        // Update available plugins list (use plain ID to match against availablePlugins)
        var parsed = Registry.parseCompositeKey(compositeKey);
        updatePluginInAvailable(parsed.pluginId, {
                                  downloaded: false,
                                  enabled: false
                                });

        if (callback)
          callback(true, null);
      } else {
        Logger.e("PluginService", "Failed to uninstall plugin:", compositeKey);
        if (callback)
          callback(false, "Failed to remove plugin files");
      }

      removeProcess.destroy();
    });

    removeProcess.running = true;
  }

  // Enable a plugin (compositeKey is the full key like "abc123:my-plugin" or plain "my-plugin")
  function enablePlugin(compositeKey, skipAddToBar) {
    if (Registry.isPluginEnabled(compositeKey)) {
      Logger.w("PluginService", "Plugin already enabled:", compositeKey);
      return true;
    }

    if (!Registry.isPluginDownloaded(compositeKey)) {
      Logger.e("PluginService", "Cannot enable: plugin not downloaded:", compositeKey);
      return false;
    }

    Registry.setPluginEnabled(compositeKey, true);
    loadPlugin(compositeKey, skipAddToBar ? null : function (manifest) {
      // Registration makes retained rows visible before the duplicate check.
      if (root.addWidgetToBar("plugin:" + compositeKey, "right")) {
        ToastService.showNotice(I18n.tr("toast.plugin-widget-added"), I18n.tr("toast.plugin-widget-added-desc", {
                                                                                "name": manifest.name || compositeKey,
                                                                                "section": "right"
                                                                              }), "puzzle");
      }
    });

    // Update available plugins list (use plain ID to match against availablePlugins)
    var parsed = Registry.parseCompositeKey(compositeKey);
    updatePluginInAvailable(parsed.pluginId, {
                              enabled: true
                            });
    root.pluginEnabled(compositeKey);

    return true;
  }

  // Selection is captured before any delayed submit; all local targets share
  // one batch, so a missing/stale target cannot leave partial placement changes.
  function _capturePlacementBatch(targets, onChanged) {
    if (!targets.length)
      return null;
    var first = targets[0];
    var commands = Settings.createRecordListEditor(first.path, first.listAddress, targets.slice(1).map(function (target) {
      return {
        path: target.path,
        listAddress: target.listAddress,
        ensure: target.ensure === true
      };
    }), {
                                                     ensure: first.ensure === true
                                                   });
    if (!commands)
      return null;
    var edits = [];
    targets.forEach(function (target, selection) {
      target.edits.forEach(function (edit) {
        edits.push(Object.assign({}, edit, {
                                   at: commands.target(selection)
                                 }));
      });
    });
    return {
      submit: function (callback) {
        return commands.submit(edits, function (result) {
          commands.detach();
          if (result.status === "admitted" && result.refreshState === "current" && typeof onChanged === "function")
            onChanged();
          if (typeof callback === "function")
            callback(result);
        });
      },
      detach: function () {
        commands.detach();
      }
    };
  }

  function _firstPlacementMonitors(monitors) {
    var names = [];
    return monitors.slice().filter(function (monitor) {
      if (names.indexOf(monitor.name) !== -1)
        return false;
      names.push(monitor.name);
      return true;
    });
  }

  function _screenWidgetTarget(name, section) {
    return {
      path: ["bar", "screenOverrides"],
      listAddress: [
        {
          field: "name",
          equals: name
        },
        {
          key: "widgets"
        },
        {
          key: section
        }
      ]
    };
  }

  function createBarWidgetInsertion(widgetId, section) {
    section = section || "right";
    var sections = ["left", "center", "right"];
    if (sections.indexOf(section) === -1)
      return null;
    if (sections.some(function (key) {
      return Settings.data.bar.widgets[key].slice().some(function (row) {
        return row.id === widgetId;
      });
    }))
      return null;
    var targets = [
          {
            path: ["bar", "widgets", section],
            listAddress: [],
            edits: [
              {
                op: "insert",
                index: Settings.data.bar.widgets[section].length,
                value: {
                  id: widgetId
                }
              }
            ]
          }
        ];
    root._firstPlacementMonitors(Settings.data.bar.screenOverrides).forEach(function (monitor) {
      if (!monitor.widgets || sections.some(function (key) {
        return (monitor.widgets[key] || []).some(function (row) {
          return row.id === widgetId;
        });
      }))
        return;
      var target = root._screenWidgetTarget(monitor.name, section);
      target.ensure = true;
      target.edits = [
            {
              op: "insert",
              index: (monitor.widgets[section] || []).length,
              value: {
                id: widgetId
              }
            }
          ];
      targets.push(target);
    });
    return root._capturePlacementBatch(targets);
  }

  function addWidgetToBar(widgetId, section) {
    var command = root.createBarWidgetInsertion(widgetId, section);
    return command ? command.submit() : false;
  }

  // Disable a plugin (compositeKey is the full key like "abc123:my-plugin" or plain "my-plugin")
  function disablePlugin(compositeKey) {
    if (!Registry.isPluginEnabled(compositeKey)) {
      Logger.w("PluginService", "Plugin already disabled:", compositeKey);
      return true;
    }

    // Remove plugin widget from bar before unloading
    var widgetId = "plugin:" + compositeKey;
    removeWidgetFromBar(widgetId);

    Registry.setPluginEnabled(compositeKey, false);
    unloadPlugin(compositeKey);

    // Update available plugins list (use plain ID to match against availablePlugins)
    var parsed = Registry.parseCompositeKey(compositeKey);
    updatePluginInAvailable(parsed.pluginId, {
                              enabled: false
                            });
    root.pluginDisabled(compositeKey);
    return true;
  }

  function _placementRemovals(rows, widgetId) {
    var edits = [];
    for (var i = rows.length - 1; i >= 0; --i) {
      if (rows[i].id === widgetId)
        edits.push({
                     op: "remove",
                     index: i
                   });
    }
    return edits;
  }

  function createBarWidgetRemoval(widgetId) {
    var sections = ["left", "center", "right"];
    var targets = [];
    sections.forEach(function (section) {
      var edits = root._placementRemovals(Settings.data.bar.widgets[section], widgetId);
      if (edits.length)
        targets.push({
                       path: ["bar", "widgets", section],
                       listAddress: [],
                       edits: edits
                     });
    });
    root._firstPlacementMonitors(Settings.data.bar.screenOverrides).forEach(function (monitor) {
      if (!monitor.widgets)
        return;
      sections.forEach(function (section) {
        var edits = root._placementRemovals(monitor.widgets[section] || [], widgetId);
        if (edits.length) {
          var target = root._screenWidgetTarget(monitor.name, section);
          target.edits = edits;
          targets.push(target);
        }
      });
    });
    return root._capturePlacementBatch(targets, function () {
      BarService.widgetsRevision++;
    });
  }

  function removeWidgetFromBar(widgetId) {
    var command = root.createBarWidgetRemoval(widgetId);
    return command ? command.submit() : false;
  }

  function createPluginDesktopRemoval(pluginId) {
    var widgetId = "plugin:" + pluginId;
    var targets = [];
    root._firstPlacementMonitors(Settings.data.desktopWidgets.monitorWidgets).forEach(function (monitor) {
      var edits = root._placementRemovals(monitor.widgets || [], widgetId);
      if (edits.length)
        targets.push({
                       path: ["desktopWidgets", "monitorWidgets"],
                       listAddress: [
                         {
                           field: "name",
                           equals: monitor.name
                         },
                         {
                           key: "widgets"
                         }
                       ],
                       edits: edits
                     });
    });
    return root._capturePlacementBatch(targets);
  }

  function removePluginDesktopWidgetsFromSettings(pluginId) {
    var command = root.createPluginDesktopRemoval(pluginId);
    return command ? command.submit() : false;
  }

  // Load plugin settings and translations before instantiating components
  // This ensures pluginApi is fully populated before being passed to createObject()
  function loadPluginData(pluginId, manifest, callback, operation) {
    // Load settings first
    _openSettingsOwner(pluginId, function (settings) {
      if (operation && !root._pluginLoadCurrent(pluginId, operation))
        return;
      if (!settings) {
        root.recordPluginError(pluginId, "settings", "Plugin settings schema or store could not be loaded; files retained");
        callback(null, {}, {}, {});
        return;
      }
      if (operation)
        operation.owner = settings;
      // Then the shared state
      loadPluginState(pluginId, function (state) {
        if (operation && !root._pluginLoadCurrent(pluginId, operation))
          return;
        // Then load translations
        loadPluginTranslationsAsync(pluginId, manifest, I18n.langCode, function (translations) {
          if (operation && !root._pluginLoadCurrent(pluginId, operation))
            return;
          // Load English fallback for non-English languages
          if (I18n.langCode !== "en") {
            loadPluginTranslationsAsync(pluginId, manifest, "en", function (fallbackTranslations) {
              if (operation && !root._pluginLoadCurrent(pluginId, operation))
                return;
              callback(settings, translations, fallbackTranslations, state);
            });
          } else {
            callback(settings, translations, {}, state);
          }
        });
      });
    });
  }

  // Load a plugin
  function _notifyBarRegistered(pluginId, component, manifest, callback) {
    if (typeof callback !== "function")
      return;
    Qt.callLater(function () {
      if (Registry.isPluginEnabled(pluginId) && root.loadedPlugins[pluginId]?.barWidget === component && BarWidgetRegistry.getWidget("plugin:" + pluginId) === component && typeof callback === "function")
        callback(manifest);
    });
  }

  function _pluginLoadCurrent(pluginId, operation) {
    if (root._pluginLoadGenerations[pluginId] !== operation || operation.cancelled)
      return false;
    if (operation.owner && (root._settingsOwners[pluginId] !== operation.owner || operation.owner.closed || operation.owner.status !== "Ready")) {
      root._finishPluginLoad(pluginId, operation, {
                               status: "failed",
                               error: {
                                 code: "plugin-owner"
                               }
                             });
      return false;
    }
    return true;
  }

  function _finishPluginLoad(pluginId, operation, result) {
    if (operation.done)
      return;
    operation.done = true;
    if (root._pluginLoads[pluginId] === operation)
      delete root._pluginLoads[pluginId];
    if (operation.startup)
      root._onPluginLoadComplete();
    var callbacks = operation.callbacks;
    operation.callbacks = [];
    Qt.callLater(function () {
      callbacks.forEach(function (callback) {
        try {
          callback(result);
        } catch (error) {
          Logger.e("PluginService", "Plugin load callback failed:", error);
        }
      });
    });
  }

  function _completePluginLoadPart(pluginId, operation) {
    if (!root._pluginLoadCurrent(pluginId, operation) || operation.done)
      return;
    operation.parts--;
    if (operation.parts !== 0)
      return;
    var failed = root.hasPluginError(pluginId);
    if (!failed) {
      var loaded = root.loadedPlugins[pluginId];
      if (loaded && loaded.barWidget)
        operation.barCallbacks.forEach(function (barCallback) {
          root._notifyBarRegistered(pluginId, loaded.barWidget, loaded.manifest, barCallback);
        });
      Logger.i("PluginService", "Plugin loaded:", pluginId);
      root.pluginLoaded(pluginId);
      if (root._pluginLoadCurrent(pluginId, operation))
        root.setupPluginFileWatcher(pluginId);
    }
    root._finishPluginLoad(pluginId, operation, failed ? {
                                                           status: "failed",
                                                           error: {
                                                             code: "plugin-components"
                                                           }
                                                         } : {
                             status: "loaded"
                           });
  }

  function _cancelPluginLoad(pluginId) {
    var operation = root._pluginLoads[pluginId];
    delete root._pluginLoadGenerations[pluginId];
    if (!operation)
      return;
    operation.cancelled = true;
    root._finishPluginLoad(pluginId, operation, {
                             status: "failed",
                             error: {
                               code: "plugin-load-cancelled"
                             }
                           });
  }

  // Full-load completion is independent of the existing bar-only callback.
  // Only a request admitted by init owns startup accounting.
  function loadPlugin(pluginId, onBarRegistered, callback, startup) {
    var pending = root._pluginLoads[pluginId];
    if (pending) {
      if (typeof callback === "function")
        pending.callbacks.push(callback);
      if (typeof onBarRegistered === "function")
        pending.barCallbacks.push(onBarRegistered);
      pending.startup = pending.startup || startup === true;
      return;
    }
    if (root.loadedPlugins[pluginId]) {
      var existing = root.loadedPlugins[pluginId];
      if (existing.barWidget)
        root._notifyBarRegistered(pluginId, existing.barWidget, existing.manifest, onBarRegistered);
      Logger.w("PluginService", "Plugin already loaded:", pluginId);
      if (startup === true)
        root._onPluginLoadComplete();
      if (typeof callback === "function")
        Qt.callLater(function () {
          callback(root.hasPluginError(pluginId) ? {
                                                     status: "failed",
                                                     error: {
                                                       code: "plugin-components"
                                                     }
                                                   } : {
                     status: "loaded"
                   });
        });
      return;
    }

    var operation = {
      done: false,
      cancelled: false,
      owner: null,
      parts: 1,
      startup: startup === true,
      callbacks: typeof callback === "function" ? [callback] : [],
      barCallbacks: typeof onBarRegistered === "function" ? [onBarRegistered] : []
    };
    root._pluginLoads[pluginId] = operation;
    root._pluginLoadGenerations[pluginId] = operation;
    if (_retiringPlugins[pluginId]) {
      _retiringPlugins[pluginId].retry = _retiringPlugins[pluginId].failed === true;
      _retiringPlugins[pluginId].callbacks.push(function (result) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        if (result.status === "failed")
          root._finishPluginLoad(pluginId, operation, result);
        else
          root._startPluginLoad(pluginId, operation);
      });
      root._settlePluginUnload(pluginId);
      return;
    }
    root._startPluginLoad(pluginId, operation);
  }

  function _startPluginLoad(pluginId, operation) {
    var manifest = Registry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot load: manifest not found for:", pluginId);
      Qt.callLater(function () {
        root._finishPluginLoad(pluginId, operation, {
                                 status: "failed",
                                 error: {
                                   code: "plugin-manifest"
                                 }
                               });
      });
      return;
    }

    var pluginDir = Registry.getPluginDir(pluginId);

    Logger.i("PluginService", "Loading plugin:", pluginId);

    // Load settings and translations FIRST, then create API and instantiate components
    loadPluginData(pluginId, manifest, function (settings, translations, fallbackTranslations, state) {
      if (!root._pluginLoadCurrent(pluginId, operation))
        return;
      if (!settings || root._settingsOwners[pluginId] !== settings || settings.closed || settings.status !== "Ready") {
        root._finishPluginLoad(pluginId, operation, {
                                 status: "failed",
                                 error: {
                                   code: "plugin-owner"
                                 }
                               });
        return;
      }
      // Create plugin API object with pre-loaded data
      var pluginApi = createPluginAPI(pluginId, manifest, settings, translations, fallbackTranslations, state);

      // Initialize plugin entry with API and manifest
      root.loadedPlugins[pluginId] = {
        barWidget: null,
        desktopWidget: null,
        launcherProvider: null,
        mainInstance: null,
        api: pluginApi,
        manifest: manifest
      };

      // Clear any previous errors for this plugin
      root.clearPluginError(pluginId);

      // Load Main.qml entry point if it exists
      if (manifest.entryPoints && manifest.entryPoints.main) {
        var mainPath = pluginDir + "/" + manifest.entryPoints.main;
        var loadVersion = Registry.pluginLoadVersions[pluginId] || 0;
        var mainComponent = Qt.createComponent("file://" + mainPath + "?v=" + loadVersion);

        if (mainComponent.status === Component.Ready) {
          // Get the plugin container from shell.qml (must be in graphics scene)
          if (!root.pluginContainer) {
            Logger.e("PluginService", "Plugin container not set. Shell must set Service.pluginContainer.");
            root.recordPluginError(pluginId, "main", "Plugin container not set");
            root._finishPluginLoad(pluginId, operation, {
                                     status: "failed",
                                     error: {
                                       code: "plugin-container"
                                     }
                                   });
            return;
          }

          // Instantiate Main.qml through the shared loader (records the error on failure)
          var mainInstance = PluginLoader.createObject(pluginId, "main", mainComponent, root.pluginContainer, pluginApi, {});
          if (!root._pluginLoadCurrent(pluginId, operation)) {
            if (mainInstance)
              mainInstance.destroy();
            return;
          }

          if (mainInstance) {
            root.loadedPlugins[pluginId].mainInstance = mainInstance;
            pluginApi.mainInstance = mainInstance;
            Logger.i("PluginService", "Loaded Main.qml for plugin:", pluginId);
          }
        } else if (mainComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "main", mainComponent.errorString());
        }
      }

      // Load bar widget component if provided (don't instantiate - BarWidgetRegistry will do that)
      if (manifest.entryPoints && manifest.entryPoints.barWidget) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        var widgetPath = pluginDir + "/" + manifest.entryPoints.barWidget;
        var widgetLoadVersion = Registry.pluginLoadVersions[pluginId] || 0;
        var widgetComponent = Qt.createComponent("file://" + widgetPath + "?v=" + widgetLoadVersion);

        if (widgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].barWidget = widgetComponent;
          pluginApi.barWidget = widgetComponent;

          // Register with BarWidgetRegistry
          var registered = BarWidgetRegistry.registerPluginWidget(pluginId, widgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded bar widget for plugin:", pluginId);

          // Now that the widget is registered, bump widgetsRevision so the bar can render it
          BarService.widgetsRevision++;
          if (!registered)
            root.recordPluginError(pluginId, "barWidget", "Plugin widget registration failed");
        } else if (widgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "barWidget", widgetComponent.errorString());
        }
      }

      // Load desktop widget component if provided (don't instantiate - DesktopWidgetRegistry will do that)
      if (manifest.entryPoints && manifest.entryPoints.desktopWidget) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        var desktopWidgetPath = pluginDir + "/" + manifest.entryPoints.desktopWidget;
        var desktopWidgetLoadVersion = Registry.pluginLoadVersions[pluginId] || 0;
        var desktopWidgetComponent = Qt.createComponent("file://" + desktopWidgetPath + "?v=" + desktopWidgetLoadVersion);

        if (desktopWidgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].desktopWidget = desktopWidgetComponent;
          pluginApi.desktopWidget = desktopWidgetComponent;

          // Register with DesktopWidgetRegistry
          DesktopWidgetRegistry.registerPluginWidget(pluginId, desktopWidgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded desktop widget for plugin:", pluginId);
        } else if (desktopWidgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "desktopWidget", desktopWidgetComponent.errorString());
        }
      }

      // Load launcher provider component if provided (don't instantiate - Launcher will do that)
      if (manifest.entryPoints && manifest.entryPoints.launcherProvider) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        var launcherProviderPath = pluginDir + "/" + manifest.entryPoints.launcherProvider;
        var launcherProviderLoadVersion = Registry.pluginLoadVersions[pluginId] || 0;
        var launcherProviderComponent = Qt.createComponent("file://" + launcherProviderPath + "?v=" + launcherProviderLoadVersion);

        if (launcherProviderComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].launcherProvider = launcherProviderComponent;
          pluginApi.launcherProvider = launcherProviderComponent;

          // Register with LauncherProviderRegistry
          LauncherProviderRegistry.registerPluginProvider(pluginId, launcherProviderComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded launcher provider for plugin:", pluginId);
        } else if (launcherProviderComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "launcherProvider", launcherProviderComponent.errorString());
        }
      }

      // Load control center widget component if provided
      if (manifest.entryPoints && manifest.entryPoints.controlCenterWidget) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        var ccWidgetPath = pluginDir + "/" + manifest.entryPoints.controlCenterWidget;
        var ccWidgetLoadVersion = Registry.pluginLoadVersions[pluginId] || 0;
        var ccWidgetComponent = Qt.createComponent("file://" + ccWidgetPath + "?v=" + ccWidgetLoadVersion);

        if (ccWidgetComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].controlCenterWidget = ccWidgetComponent;
          pluginApi.controlCenterWidget = ccWidgetComponent;

          // Register with ControlCenterWidgetRegistry
          ControlCenterWidgetRegistry.registerPluginWidget(pluginId, ccWidgetComponent, manifest.metadata);
          Logger.i("PluginService", "Loaded control center widget for plugin:", pluginId);
        } else if (ccWidgetComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "controlCenterWidget", ccWidgetComponent.errorString());
        }
      }

      // Load lock screen component if provided
      if (manifest.entryPoints && manifest.entryPoints.lockScreen) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        var lockScreenPath = pluginDir + "/" + manifest.entryPoints.lockScreen;
        var lockScreenLoadVersion = Registry.pluginLoadVersions[pluginId] || 0;
        var lockScreenComponent = Qt.createComponent("file://" + lockScreenPath + "?v=" + lockScreenLoadVersion);

        if (lockScreenComponent.status === Component.Ready) {
          root.loadedPlugins[pluginId].lockScreen = lockScreenComponent;
          LockScreenRegistry.register(pluginId, lockScreenComponent, manifest.metadata?.name ?? manifest.name);
          Logger.i("PluginService", "Loaded lock screen for plugin:", pluginId);
        } else if (lockScreenComponent.status === Component.Error) {
          root.recordPluginError(pluginId, "lockScreen", lockScreenComponent.errorString());
        }
      }

      // Load icon set data if provided (data-only, no QML)
      if (manifest.entryPoints && manifest.entryPoints.icons) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        operation.parts++;
        var iconsPath = pluginDir + "/" + manifest.entryPoints.icons;
        Logger.i("PluginService", "Loading icon set via readFile for plugin:", pluginId, "from:", iconsPath);
        var readProc = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["cat", "' + iconsPath + '"]; stdout: StdioCollector {} }', root, "iconRead_" + pluginId);
        readProc.exited.connect(function () {
          if (!root._pluginLoadCurrent(pluginId, operation)) {
            readProc.destroy();
            return;
          }
          var iconText = readProc.stdout.text;
          try {
            var iconsData = JSON.parse(iconText);
            IconRegistry.register(pluginId, iconsData, pluginDir);
            Logger.i("PluginService", "Loaded icon set for plugin:", pluginId);
          } catch (e) {
            Logger.e("PluginService", "Failed to parse icons.json for plugin:", pluginId, e);
            root.recordPluginError(pluginId, "icons", e.toString());
          }
          readProc.destroy();
          root._completePluginLoadPart(pluginId, operation);
        });
        readProc.running = true;
      }

      // Register wallpaper pools if provided (data-only)
      if (manifest.entryPoints && manifest.entryPoints.wallpapers) {
        if (!root._pluginLoadCurrent(pluginId, operation))
          return;
        operation.parts++;
        var packDir = pluginDir + "/" + manifest.entryPoints.wallpapers;
        root._registerWallpaperPacks(pluginId, packDir, manifest, operation);
      }

      root._completePluginLoadPart(pluginId, operation);
    }, operation);
  }

  // Register wallpaper pools from a pack plugin
  // Scans the pack directory: subdirectories = multiple packs; flat = single pack
  function _registerWallpaperPacks(pluginId, packDir, manifest, operation) {
    var scanProc = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["find", "' + packDir + '", "-maxdepth", "1", "-mindepth", "1", "-type", "d"]; stdout: StdioCollector {} }', root, "wpScan_" + pluginId);
    scanProc.exited.connect(function () {
      if (operation && !root._pluginLoadCurrent(pluginId, operation)) {
        scanProc.destroy();
        return;
      }
      var output = scanProc.stdout.text.trim();
      var dirs = output ? output.split('\n').filter(function (l) {
        return l.length > 0;
      }) : [];

      var pluginName = manifest.metadata?.name ?? manifest.name;

      if (dirs.length > 0) {
        // Subdirectories = one pack per subfolder
        for (var i = 0; i < dirs.length; i++) {
          var packLabel = dirs[i].split('/').pop();
          var packKey = pluginId + ":" + packLabel;
          WallpaperProviderRegistry.registerPool(packKey, {
                                                   id: packKey,
                                                   label: packLabel,
                                                   dir: dirs[i],
                                                   source: "plugin",
                                                   pluginId: pluginId
                                                 });
        }
      } else {
        // Flat directory = single pack (check for image files to confirm)
        var imgCheck = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["find", "' + packDir + '", "-maxdepth", "1", "-type", "f", "-iname", "*.jpg", "-o", "-iname", "*.png", "-o", "-iname", "*.jpeg"]; stdout: StdioCollector {} }', root, "wpImg_" + pluginId);
        imgCheck.exited.connect(function () {
          if (operation && !root._pluginLoadCurrent(pluginId, operation)) {
            imgCheck.destroy();
            return;
          }
          var imgOutput = imgCheck.stdout.text.trim();
          if (!imgOutput) {
            Logger.w("PluginService", "No wallpaper images found in pack:", packDir);
            imgCheck.destroy();
            if (operation)
              root._completePluginLoadPart(pluginId, operation);
            return;
          }
          var packKey = pluginId + ":" + pluginName;
          WallpaperProviderRegistry.registerPool(packKey, {
                                                   id: packKey,
                                                   label: pluginName,
                                                   dir: packDir,
                                                   source: "plugin",
                                                   pluginId: pluginId
                                                 });
          Logger.i("PluginService", "Registered wallpaper pool for plugin:", pluginId, "-", pluginName);
          imgCheck.destroy();
          if (operation)
            root._completePluginLoadPart(pluginId, operation);
        });
        imgCheck.running = true;
      }
      scanProc.destroy();
      if (dirs.length > 0 && operation)
        root._completePluginLoadPart(pluginId, operation);
    });
    scanProc.running = true;
  }

  // Unload a plugin
  // preserveSettings: if true, don't remove desktop widget settings (used for hot reload)
  function unloadPlugin(pluginId, preserveSettings, callback) {
    root._cancelPluginLoad(pluginId);
    if (_retiringPlugins[pluginId]) {
      _retiringPlugins[pluginId].retry = _retiringPlugins[pluginId].failed === true;
      if (typeof callback === "function")
        _retiringPlugins[pluginId].callbacks.push(callback);
      root._settlePluginUnload(pluginId);
      return;
    }
    var preferences = _settingsOwners[pluginId];
    var plugin = root.loadedPlugins[pluginId];
    var retirement = {
      owner: preferences,
      api: plugin ? plugin.api : null,
      notified: false,
      settling: false,
      callbacks: typeof callback === "function" ? [callback] : []
    };
    _retiringPlugins[pluginId] = retirement;
    if (!plugin) {
      Logger.w("PluginService", "Plugin not loaded:", pluginId);
      retirement.notified = true;
      root._settlePluginUnload(pluginId);
      return;
    }

    Logger.i("PluginService", "Unloading plugin:", pluginId);

    // Remove hot reload watcher
    removePluginFileWatcher(pluginId);

    // Unregister from BarWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.barWidget) {
      BarWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Unregister from DesktopWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.desktopWidget) {
      // Only remove settings when uninstalling, not during hot reload
      if (!preserveSettings) {
        removePluginDesktopWidgetsFromSettings(pluginId);
      }
      DesktopWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Unregister from LauncherProviderRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.launcherProvider) {
      LauncherProviderRegistry.unregisterPluginProvider(pluginId);
    }

    // Unregister from ControlCenterWidgetRegistry
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.controlCenterWidget) {
      ControlCenterWidgetRegistry.unregisterPluginWidget(pluginId);
    }

    // Unregister lock screen plugin
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.lockScreen) {
      LockScreenRegistry.unregister(pluginId);
    }

    // Unregister icon set
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.icons) {
      IconRegistry.unregister(pluginId);
    }

    // Unregister wallpaper pools
    if (plugin.manifest.entryPoints && plugin.manifest.entryPoints.wallpapers) {
      WallpaperProviderRegistry.unregisterPluginPools(pluginId);
    }

    // Destroy Main instance if any
    if (plugin.mainInstance) {
      plugin.mainInstance.destroy();
    }

    delete root.loadedPlugins[pluginId];
    root.pluginUnloaded(pluginId);
    retirement.notified = true;
    root._settlePluginUnload(pluginId);
    Logger.i("PluginService", "Unloaded plugin:", pluginId);
  }

  // Create plugin API object with pre-loaded settings and translations
  Component {
    id: settingsPreviewFactory
    PluginSettingsPreview {}
  }

  function createPluginAPI(pluginId, manifest, settings, translations, fallbackTranslations, state) {
    var pluginDir = Registry.getPluginDir(pluginId);

    var api = Qt.createQmlObject(`
      import QtQuick

      QtObject {
        // Plugin-specific
        readonly property string pluginId: "${pluginId}"
        readonly property string pluginDir: "${pluginDir}"
        property var settingsOwner: null
        property int _pendingSettingsSaves: 0
        property var _lastSettingsSave: null
        property var _settingsSaveWaiters: []
        readonly property var settingsHandle: settingsOwner ? settingsOwner.settingsScope : null
        readonly property var pluginSettings: settingsHandle ? settingsHandle.values : null
        readonly property bool settingsReady: settingsOwner !== null && !settingsOwner.closed && settingsOwner.status === "Ready"
        property var settingsPreviewOwner: null
        readonly property var settingsView: settingsPreviewOwner ? settingsPreviewOwner.values : pluginSettings
        readonly property var settingsReadOwner: settingsPreviewOwner ? settingsPreviewOwner.readOwner : settingsHandle
        property var _settingsContext: null
        readonly property var settingsContext: _settingsContext
        property var _contextLifetime: ({alive: true})
        Component.onDestruction: _contextLifetime.alive = false
        property var manifest: ({})

        // Shared state: one object per plugin, the same for every instance
        property var state: ({})
        property bool stateLoaded: false

        // Instance references (set after loading)
        property var mainInstance: null
        property var barWidget: null
        property var desktopWidget: null
        property var launcherProvider: null
        property var controlCenterWidget: null

        // Panel state: which screen the plugin's panel is currently open on (null if closed)
        property var panelOpenScreen: null

        // IPC handlers storage
        property var ipcHandlers: ({})

        // Translation storage
        property var pluginTranslations: ({})
        property var pluginFallbackTranslations: ({})  // English fallback for missing keys
        property string currentLanguage: ""
        property int translationVersion: 0  // Increments when translations change - plugins should depend on this

        // Functions will be bound below
        property var saveSettings: null
        property var createSettingsEditor: null
        property var createSettingsPreview: null
        property var saveState: null
        property var getConfig: null
        property var openPanel: null
        property var closePanel: null
        property var togglePanel: null
        property var openLauncher: null
        property var closeLauncher: null
        property var toggleLauncher: null
        property var withCurrentScreen: null
        property var tr: null
        property var trp: null
        property var hasTranslation: null
      }
    `, root, "PluginAPI_" + pluginId);

    // Set manifest
    api.manifest = manifest;

    // Set current language (can't use binding in Qt.createQmlObject string)
    api.currentLanguage = I18n.langCode;

    api.settingsOwner = settings;
    api._settingsContext = SettingsRead.context(api._contextLifetime, function () {
      return SettingsRead.values(api.settingsView, settings && !settings.closed && settings.store ? settings.store.settingsKeys : [], function (value) {
        return Settings.store.copyValue(value);
      });
    }, function () {
      return root.getPluginAPI(pluginId) === api && api.settingsReady;
    });
    api.pluginTranslations = translations || {};
    api.pluginFallbackTranslations = fallbackTranslations || {};
    // Loaded before any entry point is created (loadPluginData)
    api.state = state || {};
    api.stateLoaded = true;

    // ----------------------------------------
    // Helper function to get nested property by dot notation
    var getNestedProperty = function (obj, path) {
      var keys = path.split('.');
      var current = obj;
      for (var i = 0; i < keys.length; i++) {
        if (current === undefined || current === null) {
          return undefined;
        }
        current = current[keys[i]];
      }
      return current;
    };

    // ----------------------------------------
    // Bind functions
    // ----------------------------------------
    api.saveSettings = function (callback) {
      return root.savePluginSettings(api, api.settingsHandle, callback);
    };

    api.createSettingsEditor = function (fieldIntent) {
      return root.createPluginSettingsEditor(pluginId, api, fieldIntent === true);
    };
    api.settingsPreviewOwner = settingsPreviewFactory.createObject(api, {
                                                                     sourceReadOwner: Qt.binding(function () {
                                                                       return api.settingsHandle;
                                                                     }),
                                                                     sourceValue: Qt.binding(function () {
                                                                       return api.pluginSettings;
                                                                     }),
                                                                     draftFactory: function () {
                                                                       return root.createPluginSettingsEditor(pluginId, api);
                                                                     },
                                                                     currentOwner: function () {
                                                                       return root.getPluginAPI(pluginId) === api ? api : null;
                                                                     }
                                                                   });
    api.createSettingsPreview = function (editor) {
      return api.settingsPreviewOwner.open(editor);
    };

    // Writes the shared state to disk and reassigns it, so bindings on
    // `state` (instances forward it) re-evaluate.
    api.saveState = function () {
      savePluginState(pluginId, api.state);
      api.state = Object.assign({}, api.state);
    };

    // ----------------------------------------
    // Two-layer plugin config: plugin-shipped config.default.json merged with
    // the user's sparse override at ~/.config/atmosphera/plugins/<id>/config.json
    // (user wins). Read-only for the shipped file; async via callback.
    api.getConfig = function (callback) {
      if (api.settingsOwner)
        return api.settingsOwner.snapshotConfig(callback);
      Qt.callLater(function () {
        if (typeof callback === "function")
          callback(null);
      });
      return false;
    };

    // ----------------------------------------
    api.togglePanel = function (screen, buttonItem) {
      // Toggle this plugin's panel on the specified screen
      // buttonItem: optional, if provided the panel will position near this button
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for toggling panel");
        return false;
      }
      return togglePluginPanel(pluginId, screen, buttonItem);
    };

    // ----------------------------------------
    api.openPanel = function (screen, buttonItem) {
      // Open this plugin's panel on the specified screen
      // buttonItem: optional, if provided the panel will position near this button
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening panel");
        return false;
      }
      return openPluginPanel(pluginId, screen, buttonItem);
    };

    // ----------------------------------------
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

    // ----------------------------------------
    // Launcher provider methods
    // ----------------------------------------

    // Get the search prefix for this plugin's launcher provider
    var getSearchPrefix = function () {
      var metadata = LauncherProviderRegistry.getProviderMetadata("plugin:" + pluginId);
      var prefix = (metadata && metadata.commandPrefix) ? metadata.commandPrefix : pluginId;
      return ">" + prefix + " ";
    };

    api.openLauncher = function (screen) {
      // Open the launcher with this plugin's provider active
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for opening launcher");
        return;
      }
      PanelService.openLauncherWithSearch(screen, getSearchPrefix());
    };

    api.closeLauncher = function (screen) {
      // Close the launcher
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for closing launcher");
        return;
      }
      PanelService.closeLauncher(screen);
    };

    api.toggleLauncher = function (screen) {
      // Toggle the launcher with this plugin's provider active
      if (!screen) {
        Logger.w("PluginAPI", "No screen available for toggling launcher");
        return;
      }
      var searchPrefix = getSearchPrefix();
      var searchText = PanelService.getLauncherSearchText(screen);
      var isInThisMode = searchText.startsWith(searchPrefix);
      if (!PanelService.isLauncherOpen(screen)) {
        PanelService.openLauncherWithSearch(screen, searchPrefix);
      } else if (isInThisMode) {
        PanelService.closeLauncher(screen);
      } else {
        PanelService.setLauncherSearchText(screen, searchPrefix);
      }
    };

    // ----------------------------------------
    api.withCurrentScreen = function (callback) {
      // Detect which screen the cursor is on and call callback with that screen
      if (!root.screenDetector) {
        Logger.w("PluginAPI", "Screen detector not available, using primary screen");
        callback(Quickshell.screens[0]);
        return;
      }
      root.screenDetector.withCurrentScreen(callback);
    };

    // ----------------------------------------
    // Translation function
    api.tr = function (key, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      var translation = getNestedProperty(api.pluginTranslations, key);

      // Fallback to English if not found in current language
      if (translation === undefined || translation === null || typeof translation !== 'string') {
        translation = getNestedProperty(api.pluginFallbackTranslations, key);
      }

      // Return formatted key if translation not found in any language
      if (translation === undefined || translation === null) {
        return `!!${key}!!`;
      }

      // Ensure translation is a string
      if (typeof translation !== 'string') {
        return `!!${key}!!`;
      }

      // Handle interpolations (e.g., "Hello {name}!")
      var result = translation;
      for (var placeholder in interpolations) {
        var regex = new RegExp('\\{' + placeholder + '\\}', 'g');
        result = result.replace(regex, interpolations[placeholder]);
      }

      return result;
    };

    // ----------------------------------------
    // Plural translation function
    api.trp = function (key, count, interpolations) {
      if (typeof interpolations === 'undefined') {
        interpolations = {};
      }

      // Use key for singular, key-plural for plural
      const realKey = count === 1 ? key : `${key}-plural`;

      // Merge interpolations with count
      var finalInterpolations = {
        'count': count
      };
      for (var prop in interpolations) {
        finalInterpolations[prop] = interpolations[prop];
      }

      // Use tr() to look up the translation
      return api.tr(realKey, finalInterpolations);
    };

    // ----------------------------------------
    // Check if translation exists
    api.hasTranslation = function (key) {
      return getNestedProperty(api.pluginTranslations, key) !== undefined || getNestedProperty(api.pluginFallbackTranslations, key) !== undefined;
    };

    return api;
  }

  // Load plugin translations asynchronously
  function loadPluginTranslationsAsync(pluginId, manifest, language, callback) {
    var pluginDir = Registry.getPluginDir(pluginId);
    var translationFile = pluginDir + "/i18n/" + language + ".json";

    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${translationFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadTranslation_" + pluginId + "_" + language);

    readProcess.exited.connect(function (exitCode) {
      var translations = {};

      if (exitCode === 0) {
        try {
          translations = JSON.parse(readProcess.stdout.text);
          Logger.d("PluginService", "Loaded translations for", pluginId, "language:", language);
        } catch (e) {
          Logger.w("PluginService", "Failed to parse translations for", pluginId, "language:", language);
        }
      } else {
        Logger.d("PluginService", "No translation file for", pluginId, "language:", language);
      }

      if (callback) {
        callback(translations);
      }

      readProcess.destroy();
    });

    readProcess.running = true;
  }

  // Load the plugin's shared state (<stateDir>plugins/<key>/state.json). A missing
  // file is an empty state. A file that is not a JSON object is renamed to
  // state.json.corrupt-<ms> (kept, not deleted) and the state starts empty. The
  // rename finishes before the callback, so a save cannot race it.
  function loadPluginState(pluginId, callback) {
    var stateFile = Registry.getPluginStateFile(pluginId);
    var readProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["cat", "${stateFile}"]
        stdout: StdioCollector {}
      }
    `, root, "ReadState_" + Math.random().toString(36).substr(2, 9));

    readProcess.exited.connect(function (exitCode) {
      var text = readProcess.stdout.text;
      readProcess.destroy();
      if (exitCode !== 0) {
        // No state yet (first run)
        callback({});
        return;
      }
      var parsed = null;
      try {
        parsed = JSON.parse(text);
      } catch (e) {
        parsed = null;
      }
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        callback(parsed);
        return;
      }

      var corruptFile = stateFile + ".corrupt-" + Date.now();
      Logger.w("PluginService", "Plugin state file is corrupt, starting empty; kept as", corruptFile, "for", pluginId);
      var moveProcess = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io
        Process {
          command: ["mv", "${stateFile}", "${corruptFile}"]
        }
      `, root, "MoveState_" + Math.random().toString(36).substr(2, 9));
      moveProcess.exited.connect(function () {
        moveProcess.destroy();
        callback({});
      });
      moveProcess.running = true;
    });

    readProcess.running = true;
  }

  // Save the plugin's shared state atomically: write a temp file, then rename it
  // over state.json. The directory is created here, on first write.
  function savePluginState(pluginId, state) {
    var stateFile = Registry.getPluginStateFile(pluginId);
    var stateDirPath = stateFile.substring(0, stateFile.lastIndexOf('/'));
    var tempFile = stateFile + ".tmp-" + Math.random().toString(36).substr(2, 9);
    var delimiter = "PLUGIN_STATE_EOF_" + Math.random().toString(36).substr(2, 9);
    var quote = function (path) {
      return "'" + path.replace(/'/g, "'\\''") + "'";
    };

    // The heredoc body follows the first line; the rename runs only if the write succeeded
    var writeCmd = "mkdir -p " + quote(stateDirPath) + " && cat > " + quote(tempFile) + " << '" + delimiter + "' && mv -f " + quote(tempFile) + " " + quote(stateFile) + "\n" + JSON.stringify(state || {}, null, 2) + "\n" + delimiter + "\n";

    Logger.d("PluginService", "Saving plugin state to:", stateFile);
    Quickshell.execDetached(["sh", "-c", writeCmd]);
  }

  // Selected plugin-level editor. No runtime API or file changes until Apply;
  // loading/unloading a different API invalidates the original capture.
  // Read facts for the plugin-level field handles, taken at the same settled
  // generation as the draft baseline. The lower level is revealed only by the
  // native staged removal, never by a manifest literal copied here.
  function captureSharedSettingsFields(api) {
    var scope = api ? api.settingsHandle : null;
    if (!scope || !api.settingsOwner || api.settingsOwner.closed || root.getPluginAPI(api.pluginId) !== api)
      return null;
    var fields = Object.create(null);
    var generations = Object.create(null);
    for (var key of api.settingsOwner.store.settingsKeys) {
      var info = scope.info([key]);
      if (!Lists.settled(info))
        return null;
      generations[key] = info.publicationGeneration;
      fields[key] = {
        inheritedPresent: false,
        overridden: info.present === true && !!info.route && info.layerId === info.route.layerId && info.sourceId === info.route.sourceId
      };
    }
    return {
      fields: fields,
      current: function () {
        return root.getPluginAPI(api.pluginId) === api && !!api.settingsOwner && !api.settingsOwner.closed && api.settingsHandle === scope && Object.keys(generations).every(function (key) {
          var now = scope.info([key]);
          return Lists.settled(now) && now.publicationGeneration === generations[key];
        });
      }
    };
  }

  function createPluginSettingsEditor(pluginId, api, fieldIntent) {
    if (!api || !api.settingsHandle || root.getPluginAPI(pluginId) !== api)
      return null;
    var capture = fieldIntent === true ? captureSharedSettingsFields(api) : null;
    if (fieldIntent === true && !capture)
      return null;
    var fields = api.settingsOwner.store.settingsKeys;
    var writable = fields.length !== 0;
    var handle;
    // Informational pages own a native read-only view, not an empty draft.
    try {
      handle = writable ? api.settingsHandle.draft() : api.settingsHandle.scope([], false);
    } catch (error) {
      return null;
    }
    if (!handle)
      return null;
    var editor = preferenceEditorFactory.createObject(root, {
                                                        fields: fields,
                                                        writable: writable,
                                                        inputScope: api.settingsHandle
                                                      });
    root.retainPluginEditor(editor, api);
    editor.fieldCapture = capture;
    editor.attach(handle);
    return editor;
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

  // Find available plugin by ID
  function findAvailablePlugin(compositeKeyOrId) {
    var parsed = Registry.parseCompositeKey(compositeKeyOrId);
    var pluginId = parsed.pluginId;
    var sourceUrl = Registry.getPluginSourceUrl(compositeKeyOrId);

    for (var i = 0; i < root.availablePlugins.length; i++) {
      if (root.availablePlugins[i].id === pluginId && root.availablePlugins[i].source.url === sourceUrl) {
        return root.availablePlugins[i];
      }
    }
    return null;
  }

  // Internal flag to track if we should check for updates after registry fetch
  property bool shouldCheckUpdatesAfterFetch: false

  // Flag to track if this is the initial startup update check (for auto-update)
  property bool _isStartupCheck: false

  // Check for plugin updates (call this after availablePlugins are loaded)
  function checkForUpdates() {
    Logger.i("PluginService", "Checking for plugin updates");

    // If we have available plugins, check immediately regardless of active fetches
    if (root.availablePlugins.length > 0) {
      Logger.d("PluginService", "Available plugins already loaded, checking now");
      performUpdateCheck();
      return;
    }

    // No plugins yet - check if fetch is in progress
    if (Object.keys(activeFetches).length > 0) {
      Logger.d("PluginService", "Registry fetch in progress, will check after fetch completes");
      shouldCheckUpdatesAfterFetch = true;
      return;
    }

    // No plugins and no fetches - trigger refresh
    Logger.d("PluginService", "No available plugins yet, triggering refresh");
    shouldCheckUpdatesAfterFetch = true;
    refreshAvailablePlugins();
  }

  // Perform the actual update check
  function performUpdateCheck() {
    var updates = {};
    var pendingUpdates = {};
    var installedIds = Registry.getAllInstalledPluginIds();

    Logger.d("PluginService", "Checking", installedIds.length, "installed plugins against", root.availablePlugins.length, "available plugins");

    for (var i = 0; i < installedIds.length; i++) {
      var pluginId = installedIds[i];
      var installedManifest = Registry.getPluginManifest(pluginId);
      var availablePlugin = findAvailablePlugin(pluginId);

      if (installedManifest && availablePlugin) {
        var currentVersion = installedManifest.version;
        var availableVersion = availablePlugin.version;

        Logger.d("PluginService", "Comparing", pluginId + ":", currentVersion, "vs", availableVersion);

        // Compare versions
        if (compareVersions(availableVersion, currentVersion) > 0) {
          // Check if the available version is compatible via the single gate.
          // Pending records carry track + requiredVersion for messaging.
          var availCompat = root.checkPluginCompatibility(availablePlugin);
          if (!availCompat.compatible) {
            Logger.d("PluginService", "Pending update for", pluginId + ": requires", availCompat.track, "v" + availCompat.requiredVersion);
            pendingUpdates[pluginId] = {
              currentVersion: currentVersion,
              availableVersion: availableVersion,
              track: availCompat.track,
              requiredVersion: availCompat.requiredVersion
            };
            continue;
          }

          updates[pluginId] = {
            currentVersion: currentVersion,
            availableVersion: availableVersion
          };
          Logger.i("PluginService", "Update available for", pluginId + ":", currentVersion, "→", availableVersion);
        }
      } else if (installedManifest && !availablePlugin) {
        Logger.d("PluginService", "Plugin", pluginId, "not found in available plugins (might be from disabled source)");
      }
    }

    root.pluginUpdates = updates;
    root.pluginUpdatesPending = pendingUpdates;
    var updateCount = Object.keys(updates).length;
    var pendingCount = Object.keys(pendingUpdates).length;
    var updatesDescription = Object.keys(updates).map(function (pluginId) {
      return pluginId + ": " + updates[pluginId].currentVersion + " → " + updates[pluginId].availableVersion;
    }).join("\n");

    if (updateCount > 0) {
      Logger.i("PluginService", updateCount, "plugin update(s) available");

      if (Settings.data.plugins.notifyUpdates) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.trp("panels.plugins.update-available", updateCount) + "\n\n" + updatesDescription, "plugin", 5000, I18n.tr("panels.plugins.open-plugins-tab"), function () {
          // Open settings panel to Plugins tab on the screen where the cursor is
          if (root.screenDetector) {
            root.screenDetector.withCurrentScreen(function (screen) {
              var panel = PanelService.getPanel("settingsPanel", screen);
              if (panel) {
                panel.requestedTab = SettingsPanel.Tab.Plugins;
                panel.open();
              }
            });
          } else {
            // Fallback to primary screen if screen detector is not available
            var panel = PanelService.getPanel("settingsPanel", Quickshell.screens[0]);
            if (panel) {
              panel.requestedTab = SettingsPanel.Tab.Plugins;
              panel.open();
            }
          }
        });
      }
    } else if (pendingCount > 0) {
      Logger.i("PluginService", pendingCount, "plugin update(s) pending (require newer Noctalia)");
    } else {
      Logger.i("PluginService", "All installed plugins are up to date");
    }

    // Auto-update on startup if enabled
    if (root._isStartupCheck && Settings.data.plugins.autoUpdate && updateCount > 0) {
      Logger.i("PluginService", "Auto-updating", updateCount, "plugin(s)");
      updateAllPlugins();
    }

    root._isStartupCheck = false;
    shouldCheckUpdatesAfterFetch = false;
  }

  // Update all plugins sequentially
  function updateAllPlugins(callback) {
    var pluginIds = Object.keys(root.pluginUpdates);
    var currentIndex = 0;

    function updateNext() {
      if (currentIndex >= pluginIds.length) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.update-all-success"));
        if (callback)
          callback();
        return;
      }

      var pluginId = pluginIds[currentIndex];
      currentIndex++;

      root.updatePlugin(pluginId, function (success, error) {
        if (!success) {
          Logger.w("PluginService", "Failed to auto-update", pluginId + ":", error);
        }
        Qt.callLater(updateNext);
      });
    }

    updateNext();
  }

  // Simple version comparison (semantic versioning x.y.z)
  // Compare two PLUGIN MANIFEST versions. Both operands must be clean "x.y.z" —
  // guaranteed by Registry.validateManifest (/^\d+\.\d+\.\d+$/). Do NOT pass
  // shell/product versions: those come from git describe or the packaged VERSION file,
  // may carry a "v" prefix or git metadata, and `parseInt(x) || 0` silently substitutes
  // 0 for the unparseable segment. Use Version.compareVersions for those.
  function compareVersions(a, b) {
    var aParts = a.split('.').map(function (x) {
      return parseInt(x) || 0;
    });
    var bParts = b.split('.').map(function (x) {
      return parseInt(x) || 0;
    });

    for (var i = 0; i < 3; i++) {
      var aNum = aParts[i] || 0;
      var bNum = bParts[i] || 0;
      if (aNum > bNum)
        return 1;
      if (aNum < bNum)
        return -1;
    }
    return 0;
  }

  // Update a plugin to the latest version
  function updatePlugin(pluginId, callback) {
    var availablePlugin = root._pluginReplacements[pluginId]?.metadata || findAvailablePlugin(pluginId);
    if (!availablePlugin) {
      Logger.e("PluginService", "Plugin not found in available plugins:", pluginId);
      if (callback)
        callback(false, "Plugin not found");
      return;
    }
    return root._requestPluginReplacement(pluginId, "update", availablePlugin, function (result) {
      if (typeof callback === "function")
        callback(result.status !== "failed", result.status === "failed" ? (result.error?.code || String(result.error)) : null);
    });
  }

  function _finishPluginReplacement(pluginId, operation, result) {
    if (root._pluginReplacements[pluginId] !== operation)
      return;
    operation.running = false;
    if (result.status !== "failed") {
      delete root._pluginReplacements[pluginId];
      if (operation.kind === "update") {
        var updates = Object.assign({}, root.pluginUpdates);
        delete updates[pluginId];
        root.pluginUpdates = updates;
      } else {
        root.pluginReloaded(pluginId);
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.hot-reloaded", {
                                                                           name: operation.name
                                                                         }));
      }
    } else {
      ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.operation-failed", {
                                                                        name: operation.name,
                                                                        error: result.error?.code || String(result.error)
                                                                      }), 6000, I18n.tr("common.retry"), function () {
                                                                        if (root._pluginReplacements[pluginId] !== operation || operation.running)
                                                                          return;
                                                                        root._requestPluginReplacement(pluginId, operation.kind, operation.metadata, null);
                                                                      });
    }
    var callbacks = operation.callbacks;
    operation.callbacks = [];
    Qt.callLater(function () {
      callbacks.forEach(function (callback) {
        try {
          callback(result);
        } catch (error) {
          Logger.e("PluginService", "Plugin replacement callback failed:", error);
        }
      });
    });
  }

  function _requestPluginReplacement(pluginId, kind, metadata, callback) {
    var operation = root._pluginReplacements[pluginId];
    if (operation && operation.kind !== kind) {
      if (operation.running) {
        if (typeof callback === "function")
          Qt.callLater(function () {
            callback({
                       status: "failed",
                       error: {
                         code: "plugin-replacement-in-progress"
                       }
                     });
          });
        return false;
      }
      // A new explicit workflow may supersede a failed workflow, but its
      // requested native saves remain owned by retirement, not this record.
      operation = null;
    }
    if (!operation) {
      var manifest = Registry.getPluginManifest(pluginId);
      operation = {
        kind: kind,
        phase: "retire",
        installed: false,
        running: false,
        callbacks: [],
        enabled: Registry.isPluginEnabled(pluginId),
        loadRequired: Registry.isPluginEnabled(pluginId) || root.isPluginLoaded(pluginId),
        name: manifest?.name || pluginId,
        metadata: metadata ? JSON.parse(JSON.stringify(metadata)) : null
      };
      root._pluginReplacements[pluginId] = operation;
    }
    if (typeof callback === "function")
      operation.callbacks.push(callback);
    if (!operation.running) {
      operation.running = true;
      root._continuePluginReplacement(pluginId, operation);
    }
    return true;
  }

  function _continuePluginReplacement(pluginId, operation) {
    if (root._pluginReplacements[pluginId] !== operation)
      return;
    if (operation.phase === "retire") {
      // Keep the placements and registry choice intact. Retirement owns entry
      // destruction and final requested saves; there is no layout snapshot to
      // restore over concurrent edits and no install until this receipt succeeds.
      BarService.destroyPluginWidgetInstances(pluginId);
      for (var slotNum = 1; slotNum <= 2; slotNum++) {
        for (var s = 0; s < Quickshell.screens.length; s++) {
          var panel = PanelService.getPanel("pluginPanel" + slotNum, Quickshell.screens[s]);
          if (panel && panel.currentPluginId === pluginId) {
            panel.close();
            panel.unloadPluginPanel();
          }
        }
      }
      root.unloadPlugin(pluginId, true, function (result) {
        if (root._pluginReplacements[pluginId] !== operation)
          return;
        if (result.status === "failed") {
          root._finishPluginReplacement(pluginId, operation, result);
          return;
        }
        operation.phase = operation.kind === "update" && !operation.installed ? "install" : "load";
        if (operation.phase === "load")
          Registry.incrementPluginLoadVersion(pluginId);
        root._continuePluginReplacement(pluginId, operation);
      });
      return;
    }
    if (operation.phase === "install") {
      root.installPlugin(operation.metadata, true, function (success, error, registeredKey) {
        if (root._pluginReplacements[pluginId] !== operation)
          return;
        if (!success || registeredKey !== pluginId) {
          root._finishPluginReplacement(pluginId, operation, {
                                          status: "failed",
                                          error: {
                                            code: error || "plugin-update-identity"
                                          }
                                        });
          return;
        }
        operation.installed = true;
        operation.phase = "load";
        Registry.incrementPluginLoadVersion(pluginId);
        root._continuePluginReplacement(pluginId, operation);
      });
      return;
    }
    if (!operation.loadRequired) {
      root._finishPluginReplacement(pluginId, operation, {
                                      status: "updated"
                                    });
      return;
    }
    if (operation.enabled && !Registry.isPluginEnabled(pluginId)) {
      root._finishPluginReplacement(pluginId, operation, {
                                      status: "failed",
                                      error: {
                                        code: "plugin-disabled"
                                      }
                                    });
      return;
    }
    root.loadPlugin(pluginId, null, function (result) {
      if (root._pluginReplacements[pluginId] !== operation)
        return;
      if (result.status === "failed") {
        operation.phase = "retire";
        root._finishPluginReplacement(pluginId, operation, result);
        return;
      }
      root._finishPluginReplacement(pluginId, operation, {
                                      status: operation.kind === "update" ? "updated" : "reloaded"
                                    });
    });
  }

  // Get plugin API for a loaded plugin
  function getPluginAPI(pluginId) {
    return root.loadedPlugins[pluginId]?.api || null;
  }

  // Check if plugin is loaded
  function isPluginLoaded(pluginId) {
    return !!root.loadedPlugins[pluginId];
  }

  // A slot shows a panel of `pluginId`. Without `api` (plugin level) any instance
  // of the plugin counts; with `api` only the panel opened with that api does.
  function _panelShows(panel, pluginId, api) {
    if (panel.currentPluginId !== pluginId)
      return false;
    return !api || panel.currentPluginApi === api;
  }

  // Assigns a slot to a plugin panel and the api the panel loads with.
  function _assignPanel(panel, pluginId, api) {
    panel.currentPluginApi = api;
    panel.currentPluginId = pluginId;
  }

  // Open a plugin's panel (finds a free slot and loads the panel).
  // api: optional plugin api the panel loads with (a plugin instance's api);
  // the plugin api when omitted. A slot already showing the plugin with another
  // api is not reused for this one.
  function openPluginPanel(pluginId, screen, buttonItem, api) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot open panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    var target = api || getPluginAPI(pluginId);

    // Try to find the plugin panel slot (pluginPanel1 or pluginPanel2)
    // Priority: 1) toggle same plugin, 2) empty slot, 3) closed slot, 4) replace open slot
    var closedSlot = null;

    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel) {
        // If this slot is already showing this plugin's panel, toggle it
        if (_panelShows(panel, pluginId, api)) {
          panel.toggle(buttonItem);
          return true;
        }

        // If this slot is empty, use it
        if (panel.currentPluginId === "") {
          _assignPanel(panel, pluginId, target);
          panel.open(buttonItem);
          return true;
        }

        // Track first closed slot (panel assigned but not showing)
        if (!closedSlot && !panel.isPanelOpen) {
          closedSlot = panel;
        }
      }
    }

    // Prefer reusing a closed slot over replacing an open one
    if (closedSlot) {
      _assignPanel(closedSlot, pluginId, target);
      closedSlot.open(buttonItem);
      return true;
    }

    // If both slots are occupied and open, use slot 1 (replace existing)
    var panel1 = PanelService.getPanel("pluginPanel1", screen);
    if (panel1) {
      var wasAlreadyOpen = panel1.isPanelOpen;
      panel1.unloadPluginPanel();
      _assignPanel(panel1, pluginId, target);

      // If panel was already open, Component.onCompleted won't fire again
      // since panelContent is already loaded. We need to load the plugin manually.
      if (wasAlreadyOpen && panel1.contentLoader) {
        panel1.loadPluginPanel(pluginId);
      }

      panel1.open(buttonItem);
      return true;
    }

    Logger.e("PluginService", "Failed to find plugin panel slot");
    return false;
  }

  // Toggle a plugin's panel - close if open, open if closed
  // buttonItem: optional, if provided the panel will position near this button
  // api: optional plugin api the panel loads with (see openPluginPanel)
  function togglePluginPanel(pluginId, screen, buttonItem, api) {
    if (!isPluginLoaded(pluginId)) {
      Logger.w("PluginService", "Cannot toggle panel: plugin not loaded:", pluginId);
      return false;
    }

    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.manifest || !plugin.manifest.entryPoints || !plugin.manifest.entryPoints.panel) {
      Logger.w("PluginService", "Plugin does not provide a panel:", pluginId);
      return false;
    }

    // Check if this plugin's panel (with this api, if given) is already open in any slot
    for (var slotNum = 1; slotNum <= 2; slotNum++) {
      var panelName = "pluginPanel" + slotNum;
      var panel = PanelService.getPanel(panelName, screen);

      if (panel && _panelShows(panel, pluginId, api)) {
        // Panel is open for this plugin - toggle it (close)
        panel.toggle(buttonItem);
        return true;
      }
    }

    // Panel is not open - open it using the existing logic
    return openPluginPanel(pluginId, screen, buttonItem, api);
  }

  // ----- Error tracking functions -----

  function recordPluginError(pluginId, entryPoint, errorMessage) {
    var errors = Object.assign({}, root.pluginErrors);
    errors[pluginId] = {
      error: errorMessage,
      entryPoint: entryPoint,
      timestamp: new Date()
    };
    root.pluginErrors = errors;
    root.pluginLoadError(pluginId, entryPoint, errorMessage);
    Logger.e("PluginService", "Plugin load error [" + pluginId + "/" + entryPoint + "]:", errorMessage);
  }

  function clearPluginError(pluginId) {
    if (pluginId in root.pluginErrors) {
      var errors = Object.assign({}, root.pluginErrors);
      delete errors[pluginId];
      root.pluginErrors = errors;
    }
  }

  function getPluginError(pluginId) {
    return root.pluginErrors[pluginId] || null;
  }

  function hasPluginError(pluginId) {
    return pluginId in root.pluginErrors;
  }

  // ----- Hot reload functions -----

  // Set up file watcher for a plugin directory
  function setupPluginFileWatcher(pluginId) {
    if (!isPluginHotReloadEnabled(pluginId)) {
      return;
    }

    // Don't create duplicate watchers
    if (root.pluginFileWatchers[pluginId]) {
      return;
    }

    var manifest = Registry.getPluginManifest(pluginId);
    if (!manifest) {
      return;
    }

    var pluginDir = Registry.getPluginDir(pluginId);

    // Create a debounce timer for this plugin
    var debounceTimer = Qt.createQmlObject(`
      import QtQuick
      Timer {
        property string targetPluginId: ""
        property var reloadCallback: null
        interval: 500
        repeat: false
        onTriggered: {
          if (reloadCallback) reloadCallback(targetPluginId);
        }
      }
    `, root, "HotReloadDebounce_" + pluginId);

    // Set properties after creation to pass the callback
    debounceTimer.targetPluginId = pluginId;
    debounceTimer.reloadCallback = root.reloadPlugin;

    // Watch the manifest file - changes here indicate plugin updates
    var manifestWatcher = Qt.createQmlObject(`
      import Quickshell.Io
      FileView {
        path: "${pluginDir}/manifest.json"
        watchChanges: true
      }
    `, root, "ManifestWatcher_" + pluginId);

    var watchers = [manifestWatcher];

    // Only watch .qml and .js files, also follow symlinks since some of the plugins might have been symlinked in.
    var qmlWatcher = Qt.createQmlObject(`
        import QtQuick
        import Quickshell.Io

        import qs.Commons

        Item {
            id: root
            signal fileChanged();

            Process {
                command: [ "sh", "-c", "find -L ${pluginDir} -name '*.qml' -o -name '*.js'" ]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: line => {
                        fileWatcher.createObject(root, { path: Qt.resolvedUrl(line) });
                    }
                }
            }

            Component {
                id: fileWatcher
                FileView {
                    watchChanges: true

                    onFileChanged: {
                        root.fileChanged();
                    }
                }
            }

        }
    `, root, "QmlWatcher_" + pluginId);
    watchers.push(qmlWatcher);

    // Connect all watchers to the debounce timer
    for (var j = 0; j < watchers.length; j++) {
      watchers[j].fileChanged.connect(function () {
        debounceTimer.restart();
      });
    }

    // Create a separate debounce timer for translation reloads (lighter weight)
    var translationDebounceTimer = Qt.createQmlObject(`
      import QtQuick
      Timer {
        property string targetPluginId: ""
        property var reloadCallback: null
        interval: 300
        repeat: false
        onTriggered: {
          if (reloadCallback) reloadCallback(targetPluginId);
        }
      }
    `, root, "TranslationReloadDebounce_" + pluginId);

    translationDebounceTimer.targetPluginId = pluginId;
    translationDebounceTimer.reloadCallback = root.reloadPluginTranslations;

    // Watch the current language's translation file
    var translationWatcher = createTranslationWatcher(pluginId, pluginDir, I18n.langCode, translationDebounceTimer);

    root.pluginFileWatchers[pluginId] = {
      watchers: watchers,
      debounceTimer: debounceTimer,
      translationWatcher: translationWatcher,
      translationDebounceTimer: translationDebounceTimer,
      pluginDir: pluginDir
    };

    Logger.d("PluginService", "Set up hot reload watcher for plugin:", pluginId, "(including translations)");
  }

  // Create a translation file watcher for a specific language
  function createTranslationWatcher(pluginId, pluginDir, language, debounceTimer) {
    var translationFile = pluginDir + "/i18n/" + language + ".json";

    var watcher = Qt.createQmlObject(`
      import Quickshell.Io
      FileView {
        path: "${translationFile}"
        watchChanges: true
      }
    `, root, "TranslationWatcher_" + pluginId + "_" + language);

    watcher.fileChanged.connect(function () {
      debounceTimer.restart();
    });

    Logger.d("PluginService", "Watching translation file:", translationFile);
    return watcher;
  }

  // Update translation watchers when language changes
  function updateTranslationWatchers() {
    for (var pluginId in root.pluginFileWatchers) {
      var watcherData = root.pluginFileWatchers[pluginId];
      if (!watcherData || !watcherData.translationDebounceTimer)
        continue;

      // Destroy old translation watcher
      if (watcherData.translationWatcher) {
        watcherData.translationWatcher.destroy();
      }

      // Create new watcher for current language
      watcherData.translationWatcher = createTranslationWatcher(pluginId, watcherData.pluginDir, I18n.langCode, watcherData.translationDebounceTimer);
    }
    Logger.d("PluginService", "Updated translation watchers for language:", I18n.langCode);
  }

  // Remove file watcher for a plugin
  function removePluginFileWatcher(pluginId) {
    var watcherData = root.pluginFileWatchers[pluginId];
    if (!watcherData) {
      return;
    }

    // Destroy all watchers
    if (watcherData.watchers) {
      for (var i = 0; i < watcherData.watchers.length; i++) {
        if (watcherData.watchers[i]) {
          watcherData.watchers[i].destroy();
        }
      }
    }

    // Destroy debounce timer
    if (watcherData.debounceTimer) {
      watcherData.debounceTimer.destroy();
    }

    // Destroy translation watcher
    if (watcherData.translationWatcher) {
      watcherData.translationWatcher.destroy();
    }

    // Destroy translation debounce timer
    if (watcherData.translationDebounceTimer) {
      watcherData.translationDebounceTimer.destroy();
    }

    delete root.pluginFileWatchers[pluginId];
    Logger.d("PluginService", "Removed hot reload watcher for plugin:", pluginId);
  }

  // Reload a plugin (hot reload)
  function reloadPlugin(pluginId, callback) {
    if (!root.loadedPlugins[pluginId] && !root._retiringPlugins[pluginId] && !root._pluginReplacements[pluginId]) {
      Logger.w("PluginService", "Cannot reload: plugin not loaded:", pluginId);
      if (typeof callback === "function")
        Qt.callLater(function () {
          callback({
                     status: "failed",
                     error: {
                       code: "plugin-not-loaded"
                     }
                   });
        });
      return false;
    }

    var manifest = Registry.getPluginManifest(pluginId);
    if (!manifest) {
      Logger.e("PluginService", "Cannot reload: manifest not found for:", pluginId);
      if (typeof callback === "function")
        Qt.callLater(function () {
          callback({
                     status: "failed",
                     error: {
                       code: "plugin-manifest"
                     }
                   });
        });
      return false;
    }

    return root._requestPluginReplacement(pluginId, "reload", null, callback);
  }

  // Hot reload only translations for a plugin (lightweight, no component reload)
  function reloadPluginTranslations(pluginId) {
    var plugin = root.loadedPlugins[pluginId];
    if (!plugin || !plugin.api || !plugin.manifest) {
      Logger.w("PluginService", "Cannot reload translations: plugin not loaded:", pluginId);
      return false;
    }

    Logger.i("PluginService", "Hot reloading translations for plugin:", pluginId);

    loadPluginTranslationsAsync(pluginId, plugin.manifest, I18n.langCode, function (translations) {
      plugin.api.pluginTranslations = translations;

      // Also reload English fallback for non-English languages
      if (I18n.langCode !== "en") {
        loadPluginTranslationsAsync(pluginId, plugin.manifest, "en", function (fallbackTranslations) {
          plugin.api.pluginFallbackTranslations = fallbackTranslations;
          plugin.api.translationVersion++;

          var pluginName = plugin.manifest.name || pluginId;
          ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.translations-reloaded", {
                                                                             "name": pluginName
                                                                           }));
          Logger.i("PluginService", "Translation hot reload complete for plugin:", pluginId);
        });
      } else {
        plugin.api.pluginFallbackTranslations = {};
        plugin.api.translationVersion++;

        var pluginName = plugin.manifest.name || pluginId;
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.translations-reloaded", {
                                                                           "name": pluginName
                                                                         }));
        Logger.i("PluginService", "Translation hot reload complete for plugin:", pluginId);
      }
    });

    return true;
  }

  // Check if a certain plugin has hot reload enabled
  function isPluginHotReloadEnabled(pluginId) {
    return root.pluginHotReloadEnabled.indexOf(pluginId) !== -1;
  }

  // Toggle the hot reload state of a certain plugin
  function togglePluginHotReload(pluginId) {
    const index = root.pluginHotReloadEnabled.indexOf(pluginId);
    if (index === -1) {
      root.pluginHotReloadEnabled.push(pluginId);
      setupPluginFileWatcher(pluginId);
      Logger.i("PluginService", "Hot reload enabled for plugin:", pluginId);
    } else {
      root.pluginHotReloadEnabled.splice(index, 1);
      removePluginFileWatcher(pluginId);
      Logger.i("PluginService", "Hot reload disabled for plugin:", pluginId);
    }
  }
}
