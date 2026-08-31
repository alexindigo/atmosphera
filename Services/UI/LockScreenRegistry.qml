pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services

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
    // Tolerate a bare plugin id in the setting (hand-edited or pre-composite-key
    // configs) by resolving it to the built-in composite key.
    return root.plugins[id] || root.plugins["builtin:" + id] || root.plugins["default"];
  }
}
