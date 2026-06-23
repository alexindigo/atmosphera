pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property var iconSets: ({})
  property var activeOrder: []
  property bool _initialized: false

  Component.onCompleted: {
    root._discoverBuiltins();
    root._initialized = true;
  }

  function _discoverBuiltins() {
    var pluginsDir = Quickshell.shellDir + "/Plugins";
    root._scanIconSetDir(pluginsDir);
  }

  function _scanIconSetDir(dirPath) {
    var dir = Quickshell.temporaryFile() || null;
    var proc = Qt.createQmlObject('import Quickshell; Process { running: false }', root, "scanProc");
    if (!proc) {
      Logger.w("IconRegistry", "Failed to create process for scanning", dirPath);
      return;
    }
    proc.command = ["find", dirPath, "-maxdepth", "2", "-name", "manifest.json", "-type", "f"];
    proc.stdout = Qt.createQmlObject('import Quickshell.Io; StdioCollector {}', proc, "stdout");
    proc.stderr = Qt.createQmlObject('import Quickshell.Io; StdioCollector {}', proc, "stderr");
    proc.exited.connect(function (exitCode) {
      if (exitCode !== 0) {
        proc.destroy();
        return;
      }
      var output = proc.stdout.text().trim();
      proc.destroy();
      var files = output.split('\n').filter(function (line) {
        return line.length > 0;
      });
      for (var i = 0; i < files.length; i++) {
        root._tryLoadIconSet(files[i]);
      }
    });
    proc.running = true;
  }

  function _tryLoadIconSet(manifestPath) {
    var parts = manifestPath.split("/");
    var pluginDir = parts.slice(0, -1).join("/");
    var pluginId = parts[parts.length - 2];

    var view = Qt.createQmlObject('import Quickshell.Io; FileView { path: "' + manifestPath + '" }', root, "mfview_" + pluginId);
    view.blockLoading = false;
    view.loaded.connect(function () {
      try {
        var manifest = JSON.parse(view.text());
        if (!manifest.entryPoints || !manifest.entryPoints.icons) {
          view.destroy();
          return;
        }
        var iconsPath = pluginDir + "/" + manifest.entryPoints.icons;
        var iconsView = Qt.createQmlObject('import Quickshell.Io; FileView { path: "' + iconsPath + '" }', root, "icview_" + pluginId);
        iconsView.blockLoading = false;
        iconsView.loaded.connect(function () {
          try {
            var iconsData = JSON.parse(iconsView.text());
            root.register(pluginId, iconsData, pluginDir);
            Logger.i("IconRegistry", `Auto-discovered built-in icon set: ${pluginId}`);
          } catch (e) {
            Logger.w("IconRegistry", `Failed to parse ${iconsPath}: ${e}`);
          }
          iconsView.destroy();
        });
        iconsView.error.connect(function () {
          Logger.w("IconRegistry", `Failed to load ${iconsPath}`);
          iconsView.destroy();
        });
      } catch (e) {
        Logger.w("IconRegistry", `Failed to parse ${manifestPath}: ${e}`);
      }
      view.destroy();
    });
    view.error.connect(function () {
      Logger.w("IconRegistry", `Failed to load ${manifestPath}`);
      view.destroy();
    });
  }

  function register(pluginId, manifestData, pluginDir) {
    var entry = {
      pluginId: pluginId,
      manifest: manifestData,
      dir: pluginDir
    };
    root.iconSets[pluginId] = entry;
    root._rebuildOrder();
    Logger.i("IconRegistry", `Registered icon set: ${pluginId}`);
  }

  function unregister(pluginId) {
    delete root.iconSets[pluginId];
    root._rebuildOrder();
    Logger.i("IconRegistry", `Unregistered icon set: ${pluginId}`);
  }

  function resolve(iconId) {
    for (var i = 0; i < root.activeOrder.length; i++) {
      var setId = root.activeOrder[i];
      var set = root.iconSets[setId];
      if (!set || !set.manifest || !set.manifest.icons)
        continue;
      var entry = set.manifest.icons[iconId];
      if (!entry)
        continue;
      return root._resolveEntry(entry, set);
    }
    return null;
  }

  function _resolveEntry(entry, ownPlugin) {
    var p = ownPlugin;
    if (entry.plugin) {
      p = root.iconSets[entry.plugin];
      if (!p) {
        Logger.w("IconRegistry", `Plugin not found: ${entry.plugin}`);
        return null;
      }
    }

    if (entry.codepoint) {
      return {
        type: "font",
        char: "\\u{" + entry.codepoint + "}",
        fontSource: p.manifest.font ? "file://" + p.dir + "/" + p.manifest.font.file : ""
      };
    }
    if (entry.filename) {
      return {
        type: "svg",
        source: "file://" + p.dir + "/" + entry.filename
      };
    }

    Logger.w("IconRegistry", `Invalid entry for ${ownPlugin.pluginId}: no codepoint or filename`);
    return null;
  }

  function _rebuildOrder() {
    var all = Object.keys(root.iconSets);
    var custom = [];
    var builtins = [];
    var others = [];

    for (var i = 0; i < all.length; i++) {
      var id = all[i];
      if (id === "custom-icon-set") {
        custom.push(id);
      } else if (id === "noctalia-icons-legacy") {
        builtins.push(id);
      } else {
        others.push(id);
      }
    }

    root.activeOrder = custom.concat(others).concat(builtins);
    if (!root.iconSets["noctalia-icons-legacy"]) {
      Logger.w("IconRegistry", "Warning: noctalia-icons-legacy icon set not registered");
    }
  }
}
