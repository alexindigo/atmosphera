import QtQuick
import Quickshell
import qs.Services.UI

// Shell composition, not preference loading, owns plugin-dependent policies.
// A lock client can read Settings without constructing the plugin registry.
Scope {
  id: root
  required property var store
  required property bool settingsLoaded
  required property var pluginService
  required property var pluginRegistry

  Connections {
    target: root.pluginService
    function onPluginsFullyLoadedChanged() { root.update(); }
    function onPluginLoaded() { root.update(); }
    function onPluginUnloaded() { root.update(); }
  }
  onSettingsLoadedChanged: update()
  Component.onCompleted: update()

  function update() {
    if (!settingsLoaded || !pluginService.initialized || !pluginService.pluginsFullyLoaded || !BarWidgetRegistry.widgets || Object.keys(BarWidgetRegistry.widgets).length === 0)
      return;
    function entries(registry, normalize, retainInstalled) {
      var ids = Object.keys(registry.widgets);
      // Installed but unloadable bar plugins remain visible placeholders.
      if (retainInstalled) {
        for (var plugin of Object.keys(root.pluginRegistry.installedPlugins)) {
          var id = "plugin:" + plugin;
          if (ids.indexOf(id) === -1 && root.pluginRegistry.isPluginDownloaded(plugin))
            ids.push(id);
        }
      }
      return ids.map(function (key) {
        return {key: key, available: registry.hasWidget(key), retain: retainInstalled && key.startsWith("plugin:") && root.pluginRegistry.isPluginDownloaded(key.substring(7)), normalize: normalize && registry.widgetMetadata[key] !== undefined, defaults: normalize ? registry.widgetMetadata[key] || {} : {}};
      });
    }
    var bar = {ready: true, entries: entries(BarWidgetRegistry, true, true)};
    var shortcuts = {ready: true, entries: entries(ControlCenterWidgetRegistry, false, false)};
    var desktop = {ready: true, entries: entries(DesktopWidgetRegistry, false, false)};
    for (var section of ["left", "center", "right"])
      store.updateRecordListPolicy("bar-" + section, bar);
    for (var section of ["left", "right"])
      store.updateRecordListPolicy("shortcuts-" + section, shortcuts);
    store.updateRecordListPolicy("desktop-widgets", desktop);
  }
}
