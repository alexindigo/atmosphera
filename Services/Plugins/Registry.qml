pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../Helpers/PluginProfileMigration.js" as PluginProfileMigration
import "../../Helpers/sha256.js" as Crypto
import qs.Commons

Singleton {
  id: root

  readonly property string pluginsDir: Settings.configDir + "plugins"
  readonly property string pluginsFile: Settings.configDir + "plugins.json"

  readonly property int currentVersion: 5

  // The shell-shipped source's location (read-only distribution payload at
  // builtin/plugins/). Its identity is hashed from this path exactly like
  // any other source — no special-cased constant.
  readonly property string builtinSourceUrl: "file://" + Quickshell.shellDir + "/builtin/plugins"

  // Registry version as read from plugins.json at load (before any save
  // bumps it) — drives one-time content migrations
  property int _loadedVersion: 0

  // True while plugins.json still has the pre-v5 layout (see migrateV5). save()
  // then writes the loaded version, so an interrupted or failed migration is
  // not stamped as done and runs again on the next start.
  property bool _v5Pending: false

  Component.onCompleted: {
    ensurePluginsDirectory();
    bootstrap();
  }

  // Generate a short hash (6 characters) from a source URL
  function generateSourceHash(sourceUrl) {
    var hash = Crypto.sha256(sourceUrl);
    return hash.substring(0, 6);
  }

  // Generate composite key: plain ID for null/empty URLs (local-only
  // plugins), "<source-hash>:<id>" for everything else. One rule for every
  // source — the shell-shipped source hashes its path like any other.
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
    if (colonIndex !== -1 && colonIndex <= 6) {
      return {
        sourceHash: compositeKey.substring(0, colonIndex),
        pluginId: compositeKey.substring(colonIndex + 1)
      };
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
      root._v5Pending = adapter.version < 5;

      var needsSave = false;
      for (var i = 0; i < root.pluginSources.length; i++) {
        var src = root.pluginSources[i];
        if (!src.url && src.path) {
          src.url = "file://" + src.path;
          delete src.path;
          needsSave = true;
        }
      }

      // Self-heal: a Built-in source entry still carrying the pre-0.6
      // payload path (…/Plugins) can never load — rewrite it to the
      // current payload path. Plugin-state sourceUrls are NOT touched
      // (the v3 migration intentionally keys off the legacy hash).
      var legacyBuiltinUrl = "file://" + Quickshell.shellDir + "/Plugins";
      for (var j = 0; j < root.pluginSources.length; j++) {
        var bsrc = root.pluginSources[j];
        if (bsrc.url === legacyBuiltinUrl) {
          Logger.w("PluginRegistry", "Self-healing stale Built-in source path:", bsrc.url, "→", root.builtinSourceUrl);
          bsrc.url = root.builtinSourceUrl;
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

  // Upgrade refresh: when the shipped manifest of a built-in plugin is newer
  // than the installed copy, re-copy it into the user dir. Keeps built-in
  // installs fresh across shell updates now that all plugins run from the
  // user folder (settings live outside the plugin dir and are preserved;
  // a legacy in-dir settings.json is carried over).
  function refreshBuiltinPlugins(done) {
    var toCheck = [];
    for (var key in root.pluginStates) {
      var state = root.pluginStates[key];
      if (state && state.sourceUrl === root.builtinSourceUrl) {
        toCheck.push(key);
      }
    }

    if (toCheck.length === 0) {
      done();
      return;
    }

    var script = `
import json, os, shutil, sys

src_root, dst_root = sys.argv[1], sys.argv[2]

def vp(v):
    try:
        return [int(x) for x in str(v).split('.') if x.strip().isdigit()]
    except Exception:
        return []

for key in sys.argv[3:]:
    name = key.split(':', 1)[1] if ':' in key else key
    src_dir = os.path.join(src_root, name)
    dst_dir = os.path.join(dst_root, key)
    try:
        src_ver = json.load(open(os.path.join(src_dir, 'manifest.json'))).get('version', '0')
        dst_ver = json.load(open(os.path.join(dst_dir, 'manifest.json'))).get('version', '0')
    except Exception:
        continue
    if vp(src_ver) > vp(dst_ver):
        legacy_settings = os.path.join(dst_dir, 'settings.json')
        saved = None
        if os.path.exists(legacy_settings):
            saved = open(legacy_settings, 'rb').read()
        shutil.rmtree(dst_dir, ignore_errors=True)
        shutil.copytree(src_dir, dst_dir)
        if saved is not None:
            with open(legacy_settings, 'wb') as f:
                f.write(saved)
        print('refreshed', key)
`;

    var refreshProcess = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        stdout: StdioCollector {}
      }
    `, root, "RefreshBuiltinPlugins");
    // Command assigned after creation (array interpolation into inline QML is fragile)
    refreshProcess.command = ["python3", "-c", script, Quickshell.shellDir + "/builtin/plugins", root.pluginsDir].concat(toCheck);

    refreshProcess.exited.connect(function () {
      var out = (String(refreshProcess.stdout.text || "")).trim();
      if (out) {
        Logger.i("PluginRegistry", "Upgrade refresh:", out.split("\n").join(", "));
      }
      refreshProcess.destroy();
      done();
    });

    refreshProcess.running = true;
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
      root.migrateV5(function () {
        root.refreshBuiltinPlugins(done);
      });
    });
  }

  // v5 (planned by Helpers/PluginProfileMigration.js, planV5): built-in plugin
  // keys move to the current source hash, retired built-ins are removed, and
  // the placements and lock-screen reference that use them are rewritten.
  // Order: list inputs, plan, backup, folder and settings-file moves, then
  // plugins.json, then settings references. A failed step stops the migration
  // with _v5Pending still set, so the next start runs it again.
  function migrateV5(done) {
    if (root._loadedVersion >= 5) {
      done();
      return;
    }
    var shellPlugins = Quickshell.shellDir + "/builtin/plugins";
    root.runProcess("ListShippedPlugins", ["sh", "-c", 'find "$1" -mindepth 2 -maxdepth 2 -name manifest.json -type f 2>/dev/null; true', "sh", shellPlugins], function (exitCode, shippedText) {
      var shippedIds = [];
      var paths = shippedText.trim() ? shippedText.trim().split("\n") : [];
      for (var i = 0; i < paths.length; i++)
        shippedIds.push(paths[i].split("/").slice(-2)[0]);

      root.runProcess("ListPluginSettings", ["sh", "-c", 'find "$1" -maxdepth 1 -type f -name "*.json" -printf "%f\\n" 2>/dev/null; true', "sh", Settings.configDir + "settings/plugins"], function (exitCode2, namesText) {
        // Names without the .json extension, as the planner expects.
        var files = [];
        var names = namesText.trim() ? namesText.trim().split("\n") : [];
        for (var j = 0; j < names.length; j++) {
          if (names[j].endsWith(".json"))
            files.push(names[j].slice(0, -5));
        }
        root._planV5Migration(shippedIds, files, done);
      });
    });
  }

  function _planV5Migration(shippedIds, settingsFiles, done) {
    var currentHash = root.generateSourceHash(root.builtinSourceUrl);
    var plan = PluginProfileMigration.planV5({
                                               states: root.pluginStates,
                                               sources: root.pluginSources,
                                               shippedIds: shippedIds,
                                               builtinSourceUrl: root.builtinSourceUrl,
                                               currentHash: currentHash,
                                               pluginSettingsFiles: settingsFiles
                                             });
    var sourcesChanged = JSON.stringify(plan.sources) !== JSON.stringify(root.pluginSources);
    if (plan.rekeys.length === 0 && plan.removals.length === 0 && plan.dropped.length === 0 && plan.settingsFileMoves.length === 0 && !sourcesChanged) {
      root._v5Pending = false;
      done();
      return;
    }

    for (var r = 0; r < plan.rekeys.length; r++)
      Logger.i("PluginRegistry", "v5 migration: rekeyed", plan.rekeys[r].from, "->", plan.rekeys[r].to);
    for (var m = 0; m < plan.removals.length; m++)
      Logger.i("PluginRegistry", "v5 migration: removed retired built-in plugin", plan.removals[m]);
    for (var d = 0; d < plan.dropped.length; d++)
      Logger.i("PluginRegistry", "v5 migration: dropped", plan.dropped[d], "(its current key already exists)");
    for (var u = 0; u < plan.unsourced.length; u++)
      Logger.i("PluginRegistry", plan.unsourced[u] + " is a local plugin without a source; it won't receive updates");

    var backupDir = Settings.configDir + "backups/plugins-v5-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
    root._backupV5(plan, backupDir, function (ok) {
      if (!ok) {
        Logger.e("PluginRegistry", "v5 migration: backup failed, profile left unchanged:", backupDir);
        done();
        return;
      }
      root._moveV5Files(plan, function (ok2) {
        if (!ok2) {
          Logger.e("PluginRegistry", "v5 migration: file moves failed; plugins.json left at its loaded version");
          done();
          return;
        }
        root.pluginStates = plan.states;
        root.pluginSources = plan.sources;
        root._v5Pending = false;
        root.save();
        root._whenSettingsLoaded(function () {
          root._rewriteSettingsV5(plan, currentHash);
          done();
        });
      });
    });
  }

  // Copies every folder and settings file the plan touches into backupDir.
  // Missing items are skipped; any copy error fails the backup.
  function _backupV5(plan, backupDir, done) {
    var pd = root.pluginsDir;
    var sd = Settings.configDir + "settings/plugins";
    var s = "set -e\n";
    s += "mkdir -p " + root._shq(Settings.configDir + "backups") + "\n";
    s += "mkdir " + root._shq(backupDir) + "\n";
    s += "mkdir -p " + root._shq(backupDir + "/plugins") + " " + root._shq(backupDir + "/settings/plugins") + "\n";
    s += "cp -a " + root._shq(root.pluginsFile) + " " + root._shq(backupDir + "/") + "\n";
    var folders = [];
    for (var r = 0; r < plan.rekeys.length; r++)
      folders.push(plan.rekeys[r].from);
    folders = folders.concat(plan.removals, plan.dropped);
    for (var i = 0; i < folders.length; i++) {
      var folder = root._shq(pd + "/" + folders[i]);
      s += "if [ -e " + folder + " ]; then cp -a " + folder + " " + root._shq(backupDir + "/plugins/") + "; fi\n";
    }
    for (var f = 0; f < plan.settingsFileMoves.length; f++) {
      var file = root._shq(sd + "/" + plan.settingsFileMoves[f].from);
      s += "if [ -e " + file + " ]; then cp -a " + file + " " + root._shq(backupDir + "/settings/plugins/") + "; fi\n";
    }
    root.runProcess("BackupPluginsV5", ["sh", "-c", s], function (exitCode, out, err) {
      if (exitCode !== 0)
        Logger.e("PluginRegistry", "v5 backup script failed:", err.trim());
      done(exitCode === 0);
    });
  }

  // Applies the plan's folder and settings-file moves. Rekeyed folders get a
  // fresh shipped copy (built in a temp dir, then renamed into place) before the
  // old folder is removed. Every step is idempotent, so a repeat run is safe.
  function _moveV5Files(plan, done) {
    var pd = root.pluginsDir;
    var sd = Settings.configDir + "settings/plugins";
    var shipped = Quickshell.shellDir + "/builtin/plugins";
    var s = "set -e\n";
    for (var r = 0; r < plan.rekeys.length; r++) {
      var rk = plan.rekeys[r];
      var tmp = root._shq(pd + "/.migrating-" + rk.to);
      var dest = root._shq(pd + "/" + rk.to);
      s += "rm -rf " + tmp + "\n";
      s += "mkdir " + tmp + "\n";
      s += "cp -r " + root._shq(shipped + "/" + rk.id + "/.") + " " + tmp + "/\n";
      // Legacy in-dir settings: still read when settings/plugins/<key>.json is
      // missing (Service.qml getLegacyPluginSettingsFile fallback), so carry it over.
      s += "if [ -f " + root._shq(pd + "/" + rk.from + "/settings.json") + " ]; then cp -a " + root._shq(pd + "/" + rk.from + "/settings.json") + " " + tmp + "/settings.json; fi\n";
      s += "rm -rf " + dest + "\n";
      s += "mv " + tmp + " " + dest + "\n";
      s += "rm -rf " + root._shq(pd + "/" + rk.from) + "\n";
    }
    var gone = plan.removals.concat(plan.dropped);
    for (var g = 0; g < gone.length; g++)
      s += "rm -rf " + root._shq(pd + "/" + gone[g]) + "\n";
    for (var f = 0; f < plan.settingsFileMoves.length; f++) {
      var mv = plan.settingsFileMoves[f];
      var from = root._shq(sd + "/" + mv.from);
      var to = root._shq(sd + "/" + mv.to);
      s += "if [ -e " + from + " ] && [ ! -e " + to + " ]; then mv " + from + " " + to + "; fi\n";
    }
    root.runProcess("MigrateV5Files", ["sh", "-c", s], function (exitCode, out, err) {
      if (exitCode !== 0)
        Logger.e("PluginRegistry", "v5 file move script failed:", err.trim());
      done(exitCode === 0);
    });
  }

  // Rewrites the placements and the lock-screen reference that name a rekeyed
  // or dropped key. Only the id changes; instance settings are kept. Settings
  // are written through Settings.data, and only groups that changed are assigned.
  function _rewriteSettingsV5(plan, currentHash) {
    var keyMap = PluginProfileMigration.keyMapFor(plan, currentHash);
    if (Object.keys(keyMap).length === 0)
      return;

    var sections = ["left", "center", "right"];
    var bar = Settings.data.bar.widgets;
    var shortcuts = Settings.data.controlCenter.shortcuts;
    var rw = PluginProfileMigration.rewriteSettingsReferences({
                                                                barWidgets: {
                                                                  left: bar.left,
                                                                  center: bar.center,
                                                                  right: bar.right
                                                                },
                                                                screenOverrides: Settings.data.bar.screenOverrides,
                                                                controlCenterShortcuts: {
                                                                  left: shortcuts.left,
                                                                  right: shortcuts.right
                                                                },
                                                                monitorWidgets: Settings.data.desktopWidgets.monitorWidgets,
                                                                lockScreenPlugin: Settings.data.general.lockScreenPlugin
                                                              }, keyMap);

    if (rw.touched.barWidgets) {
      for (var i = 0; i < sections.length; i++)
        Settings.data.bar.widgets[sections[i]] = rw.barWidgets[sections[i]];
    }
    if (rw.touched.screenOverrides)
      Settings.data.bar.screenOverrides = rw.screenOverrides;
    if (rw.touched.controlCenterShortcuts) {
      Settings.data.controlCenter.shortcuts.left = rw.controlCenterShortcuts.left;
      Settings.data.controlCenter.shortcuts.right = rw.controlCenterShortcuts.right;
    }
    if (rw.touched.monitorWidgets)
      Settings.data.desktopWidgets.monitorWidgets = rw.monitorWidgets;
    if (rw.touched.lockScreenPlugin)
      Settings.data.general.lockScreenPlugin = rw.lockScreenPlugin;

    if (rw.touched.barWidgets || rw.touched.screenOverrides || rw.touched.controlCenterShortcuts || rw.touched.monitorWidgets || rw.touched.lockScreenPlugin) {
      Logger.i("PluginRegistry", "v5 migration: rewrote placement references to rekeyed plugins");
      Settings.saveImmediate();
    }
  }

  // Runs callback once Settings has loaded (immediately if it already has).
  function _whenSettingsLoaded(callback) {
    if (Settings.isLoaded) {
      callback();
      return;
    }
    var called = false;
    Settings.settingsLoaded.connect(function () {
      if (called)
        return;
      called = true;
      callback();
    });
  }

  // Runs a command in a Process and hands back its exit code and output.
  function runProcess(name, command, done) {
    var proc = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        stdout: StdioCollector {}
        stderr: StdioCollector {}
      }
    `, root, name);
    proc.command = command;
    proc.exited.connect(function (exitCode) {
      var out = String(proc.stdout.text || "");
      var err = String(proc.stderr.text || "");
      proc.destroy();
      done(exitCode, out, err);
    });
    proc.running = true;
  }

  // Single-quotes a value for sh.
  function _shq(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
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
    adapter.version = root._v5Pending ? root._loadedVersion : root.currentVersion;
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
    // Uniform semantics: plugins always run from the user-owned install copy.
    // The source tree (builtin/plugins/) is read-only distribution; installed
    // copies stay fresh via the upgrade refresh (refreshBuiltinPlugins).
    return root.pluginsDir + "/" + pluginId;
  }

  // Get plugin settings file path (user-owned area: survives plugin
  // uninstall/reinstall, which wipes only the plugin's code dir)
  function getPluginSettingsFile(pluginId) {
    return Settings.configDir + "settings/plugins/" + pluginId + ".json";
  }

  // Plugin shared state file (plugin api `state`, see Service.saveState)
  function getPluginStateFile(pluginId) {
    return Settings.stateDir + "plugins/" + pluginId + "/state.json";
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
