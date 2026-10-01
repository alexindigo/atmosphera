pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Services.Plugins
import qs.Services.UI

Singleton {
  id: root

  property var plugins: ({})
  property var pluginNames: ({})

  function register(pluginId, component, name) {
    root.plugins[pluginId] = component;
    root.pluginNames[pluginId] = name;
  }

  function unregister(pluginId) {
    delete root.plugins[pluginId];
    delete root.pluginNames[pluginId];
  }

  function selectedComponent() {
    var id = Settings.data.general.lockScreenPlugin || "default";
    if (id === "external")
      return null;
    return root.plugins[id] || root.plugins["default"];
  }

  // Migration heal: a configured selection that no longer resolves
  // (e.g. a stale composite key from a renamed source URL) is re-linked
  // by bare id to the installed plugin, or surfaced — never silently
  // dropped to the default.
  Connections {
    target: Service
    function onAllPluginsLoaded() {
      root._healSelection();
    }
  }

  function _healSelection() {
    var configured = Settings.data.general.lockScreenPlugin;
    if (!configured || configured === "" || configured === "default" || configured === "external")
      return;
    if (Registry.installedPlugins[configured])
      return; // resolves

    var bare = configured.replace(/^[a-f0-9]{6}:/, "");
    var installed = Registry.installedPlugins;
    var found = "";
    for (var key in installed) {
      if (key === bare || key.endsWith(":" + bare)) {
        found = key;
        break;
      }
    }
    if (found !== "") {
      Logger.w("LockScreenRegistry", "Lock screen plugin '" + configured + "' not installed; re-linked to '" + found + "'");
      Settings.data.general.lockScreenPlugin = found;
      ToastService.showNotice(I18n.tr("toast.lockscreen-plugin-relinked"), I18n.tr("toast.lockscreen-plugin-relinked-desc", {
                                                                                     "id": bare
                                                                                   }), "preferences-system-power");
    } else {
      Logger.w("LockScreenRegistry", "Lock screen plugin '" + configured + "' not installed; using the built-in lock screen");
      ToastService.showWarning(I18n.tr("toast.lockscreen-plugin-missing"), I18n.tr("toast.lockscreen-plugin-missing-desc", {
                                                                                     "id": bare
                                                                                   }), "preferences-system-power");
    }
  }
}
