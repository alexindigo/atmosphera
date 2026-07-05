pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property var iconSets: ({})
  property var activeOrder: []
  property var resolved: ({})

  // Register a plugin's icon set
  function register(pluginId, manifestData, pluginDir) {
    var entry = {
      pluginId: pluginId,
      manifest: manifestData,
      dir: pluginDir,
      fontName: ""
    };

    // Load the plugin's font if declared
    if (manifestData && manifestData.font && manifestData.font.file) {
      var fontPath = "file://" + pluginDir + "/" + manifestData.font.file;
      entry._fontLoader = Qt.createQmlObject('import QtQuick; FontLoader { source: "' + fontPath + '" }', root, "font_" + pluginId);
      entry._fontLoader.statusChanged.connect(function () {
        if (entry._fontLoader.status === FontLoader.Ready) {
          entry.fontName = entry._fontLoader.name;
          root.rebuildResolved();
        }
      });
    }

    root.iconSets[pluginId] = entry;
    root._rebuildOrder();
    root.rebuildResolved();
    Logger.i("IconRegistry", "Registered icon set:", pluginId);
  }

  // Unregister a plugin's icon set
  function unregister(pluginId) {
    var entry = root.iconSets[pluginId];
    if (entry && entry._fontLoader) {
      entry._fontLoader.destroy();
    }
    delete root.iconSets[pluginId];
    root._rebuildOrder();
    root.rebuildResolved();
    Logger.i("IconRegistry", "Unregistered icon set:", pluginId);
  }

  // Resolve a single icon by name (falls back to bundled font)
  function resolve(iconId) {
    for (var i = 0; i < root.activeOrder.length; i++) {
      var setId = root.activeOrder[i];
      var set = root.iconSets[setId];
      if (!set || !set.manifest || !set.manifest.icons)
        continue;

      // Check if there's an alias map for this set
      var targetName = iconId;
      if (set.manifest.aliases && set.manifest.aliases[iconId] !== undefined) {
        targetName = set.manifest.aliases[iconId];
      }

      var entry = set.manifest.icons[targetName];
      if (!entry)
        continue;
      return root._resolveEntry(entry, set);
    }
    return null;
  }

  // Rebuild the resolved map from all active icon sets
  function rebuildResolved() {
    var newResolved = {};
    for (var si = 0; si < root.activeOrder.length; si++) {
      var setId = root.activeOrder[si];
      var set = root.iconSets[setId];
      if (!set || !set.manifest || !set.manifest.icons)
        continue;

      var iconKeys = Object.keys(set.manifest.icons);
      for (var ki = 0; ki < iconKeys.length; ki++) {
        var iconKey = iconKeys[ki];
        if (newResolved[iconKey] !== undefined)
          continue; // higher-priority set already resolved this key
        var iconEntry = set.manifest.icons[iconKey];
        newResolved[iconKey] = root._resolveEntry(iconEntry, set);
      }
    }
    root.resolved = newResolved;
    root.resolvedChanged();
  }

  // Translate an icon entry to a usable form
  function _resolveEntry(entry, ownPlugin) {
    var p = ownPlugin;
    if (entry.plugin) {
      p = root.iconSets[entry.plugin];
      if (!p) {
        // Try matching by bare plugin ID (strip hash prefix)
        for (var key in root.iconSets) {
          if (root._barePluginId(key) === entry.plugin) {
            p = root.iconSets[key];
            break;
          }
        }
      }
      if (!p) {
        Logger.w("IconRegistry", "Plugin not found:", entry.plugin);
        return null;
      }
    }

    if (entry.codepoint) {
      return {
        type: "font",
        char: String.fromCodePoint(parseInt(entry.codepoint, 16)),
        fontFamily: p && p.fontName ? p.fontName : (Icons.fontFamily || "")
      };
    }
    if (entry.filename) {
      return {
        type: "svg",
        source: "file://" + p.dir + "/" + entry.filename
      };
    }

    Logger.w("IconRegistry", "Invalid entry for", ownPlugin.pluginId, ": no codepoint or filename");
    return null;
  }

  // Build resolution order: custom first, then others, then legacy as floor
  function _rebuildOrder() {
    var all = Object.keys(root.iconSets);
    var custom = [];
    var builtins = [];
    var others = [];

    for (var i = 0; i < all.length; i++) {
      var id = all[i];
      var bareId = root._barePluginId(id);
      if (bareId === "custom-icon-set") {
        custom.push(id);
      } else if (bareId === "noctalia-icons-legacy") {
        builtins.push(id);
      } else {
        others.push(id);
      }
    }

    root.activeOrder = custom.concat(others).concat(builtins);
  }

  function _barePluginId(key) {
    var ci = key.indexOf(":");
    if (ci > 0 && ci <= 6) {
      return key.substring(ci + 1);
    }
    return key;
  }
}
