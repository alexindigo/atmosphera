pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  property var iconSets: ({})
  property var activeOrder: []
  property bool _initialized: false

  Component.onCompleted: {
    root._initialized = true;
  }

  function register(pluginId, manifestData, pluginDir) {
    var entry = {
      pluginId: pluginId,
      manifest: manifestData,
      dir: pluginDir
    };
    root.iconSets[pluginId] = entry;
    root._rebuildOrder();
    Logger.i("IconRegistry", "Registered icon set:", pluginId);
  }

  function unregister(pluginId) {
    delete root.iconSets[pluginId];
    root._rebuildOrder();
    Logger.i("IconRegistry", "Unregistered icon set:", pluginId);
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
        Logger.w("IconRegistry", "Plugin not found:", entry.plugin);
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

    Logger.w("IconRegistry", "Invalid entry for", ownPlugin.pluginId, ": no codepoint or filename");
    return null;
  }

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
    var hasLegacy = all.some(function (key) {
      return root._barePluginId(key) === "noctalia-icons-legacy";
    });
    if (!hasLegacy) {
      Logger.w("IconRegistry", "Warning: noctalia-icons-legacy icon set not registered");
    }
  }

  function _barePluginId(key) {
    var ci = key.indexOf(":");
    if (ci > 0 && ci <= 6) {
      return key.substring(ci + 1);
    }
    return key;
  }
}
