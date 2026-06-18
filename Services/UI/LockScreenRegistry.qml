pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Noctalia

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
    return root.plugins[id] || root.plugins["default"];
  }
}
