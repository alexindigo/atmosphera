pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "ActionCommand.js" as ActionCommand
import qs.Commons
import qs.Services.Compositor
import qs.Services.Plugins

Singleton {
  id: root

  readonly property bool ready: _coreLoaded
  property var actions: []
  property int revision: 0
  property bool _coreLoaded: false
  property var _coreActions: []
  readonly property string _compositor: CompositorService.isNiri ? "niri" : CompositorService.isHyprland ? "hyprland" : CompositorService.isSway ? "sway" : CompositorService.isMango ? "mango" : ""

  function match(command) {
    return ActionCommand.recognize(command, actions);
  }

  function compose(action, values) {
    return ActionCommand.compose(action, values);
  }

  function displayLabel(action, values) {
    return ActionCommand.displayLabel(action, values);
  }

  function rebuild() {
    var plugins = Service.loadedPlugins;
    var keys = Object.keys(plugins).sort(function (a, b) {
      var aId = plugins[a].manifest.id;
      var bId = plugins[b].manifest.id;
      return aId < bId ? -1 : aId > bId ? 1 : a < b ? -1 : a > b ? 1 : 0;
    });
    var context = {
      compositor: _compositor,
      loadedPluginIds: keys.map(function (key) {
        return plugins[key].manifest.id;
      })
    };
    var output = [];
    var commands = Object.create(null);
    var pluginCore = Object.create(null);
    function append(action, origin, key, section, group, ids) {
      var verdict = ActionCommand.validate(action, origin);
      if (!verdict.valid || ids.indexOf(action.id) >= 0) {
        var reason = verdict.valid ? "duplicate id" : verdict.error;
        if (origin === "core")
          Logger.e("ActionRegistry", key + ": " + reason);
        else
          Logger.w("ActionRegistry", key + ": " + reason);
        return;
      }
      ids.push(action.id);
      if (!ActionCommand.available(action, context))
        return;
      var command = ActionCommand.compose(action, {});
      if (commands[command]) {
        Logger.w("ActionRegistry", key + ": duplicate composed command " + command);
        return;
      }
      commands[command] = true;
      var row = {
        key: key + "/" + action.id,
        section: section,
        group: group,
        label: action.label,
        description: action.description,
        icon: action.icon,
        command: action.command,
        arguments: action.arguments || []
      };
      if (action.requiresPlugin) {
        if (!pluginCore[action.requiresPlugin])
          pluginCore[action.requiresPlugin] = [];
        pluginCore[action.requiresPlugin].push(row);
      } else {
        output.push(row);
      }
    }
    var ids = [];
    _coreActions.forEach(function (action) {
      append(action, "core", "core", "Atmosphera", action && action.group || "", ids);
    });
    keys.forEach(function (key) {
      var plugin = plugins[key];
      var manifest = plugin.manifest;
      (pluginCore[manifest.id] || []).forEach(function (row) {
        row.section = "Plugins";
        row.group = manifest.name;
        output.push(row);
      });
      delete pluginCore[manifest.id];
      if (!plugin.mainInstance || manifest.actions === undefined)
        return;
      if (!Array.isArray(manifest.actions)) {
        Logger.w("ActionRegistry", key + ": actions must be a list");
        return;
      }
      var pluginIds = [];
      manifest.actions.forEach(function (action) {
        append(action, "plugin", key, "Plugins", manifest.name, pluginIds);
      });
    });
    actions = output;
    revision++;
  }

  FileView {
    path: Quickshell.shellDir + "/Assets/Actions/core.json"
    onLoaded: {
      try {
        var catalog = JSON.parse(text());
        if (catalog.version !== 1 || !Array.isArray(catalog.actions) || Object.keys(catalog).sort().join(",") !== "actions,version")
          throw new Error("expected version 1 and actions");
        root._coreActions = catalog.actions;
      } catch (error) {
        Logger.e("ActionRegistry", "Cannot read core actions: " + error);
        root._coreActions = [];
      }
      root._coreLoaded = true;
      root.rebuild();
    }
    onLoadFailed: function (error) {
      Logger.e("ActionRegistry", "Cannot load core actions: " + error);
      root._coreLoaded = true;
      root.rebuild();
    }
  }

  Connections {
    target: Service
    function onPluginLoaded() {
      root.rebuild();
    }
    function onPluginUnloaded() {
      root.rebuild();
    }
    function onPluginReloaded() {
      root.rebuild();
    }
    function onAllPluginsLoaded() {
      root.rebuild();
    }
  }

  on_CompositorChanged: rebuild()
  Component.onCompleted: rebuild()
}
