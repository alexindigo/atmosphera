pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

// Plugin instances (plugin-instances design, section 4). One instance api per
// placed plugin piece. A placement is one of:
//   {kind:"bar", list:"global"|<screenName>, section, index}
//   {kind:"controlCenter", section:"left"|"right", index}
//   {kind:"desktop", screenName, index}
// The entry at that placement stores the instance's overrides under
// `instanceSettings`; only changed values are kept there.
Singleton {
  id: root

  // Bumped after every instance save; instance apis read it so their effective
  // settings re-evaluate.
  property int revision: 0

  // "<pluginKey>|<placement json>" -> { base, api }
  property var _cache: ({})

  Component {
    id: apiComponent
    PluginInstanceApi {}
  }

  // A plugin reload gives the plugin a new api; its instances must follow it.
  Connections {
    target: Service
    function onPluginUnloaded(pluginId) {
      root._dropPlugin(pluginId);
    }
    function onPluginLoaded(pluginId) {
      root._dropPlugin(pluginId);
    }
  }

  // The list a bar widget on this screen belongs to: the screen's own list when
  // the screen draws one (the same rule as Settings.getBarWidgetsForScreen),
  // otherwise the shared global list.
  function barList(screenName) {
    if (!screenName)
      return "global";
    return Settings.getBarWidgetsForScreen(screenName) === Settings.data.bar.widgets ? "global" : screenName;
  }

  // The api of the instance at `placement` for the plugin `pluginKey`. The same
  // placement returns the same object while the plugin stays loaded.
  function apiFor(pluginKey, placement) {
    var base = Service.getPluginAPI(pluginKey);
    if (!base || !placement)
      return null;
    var key = pluginKey + "|" + JSON.stringify(placement);
    var cached = root._cache[key];
    if (cached && cached.base === base)
      return cached.api;
    var api = apiComponent.createObject(root, {
                                          "base": base,
                                          "placement": JSON.parse(JSON.stringify(placement))
                                        });
    root._cache[key] = {
      "base": base,
      "api": api
    };
    return api;
  }

  function _dropPlugin(pluginKey) {
    var prefix = pluginKey + "|";
    var next = {};
    for (var key in root._cache) {
      if (key.indexOf(prefix) !== 0)
        next[key] = root._cache[key];
    }
    root._cache = next;
  }

  // The entry object at a placement, or null when the placement is empty.
  function entryFor(placement) {
    if (!placement)
      return null;
    var row = null;
    if (placement.kind === "bar") {
      var lists = placement.list === "global" ? Settings.data.bar.widgets : Settings.getBarWidgetsForScreen(placement.list);
      row = lists ? lists[placement.section] : null;
    } else if (placement.kind === "controlCenter") {
      row = Settings.data.controlCenter.shortcuts[placement.section];
    } else if (placement.kind === "desktop") {
      var monitors = Settings.data.desktopWidgets.monitorWidgets || [];
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name === placement.screenName) {
          row = monitors[i].widgets;
          break;
        }
      }
    }
    return (row && row[placement.index]) || null;
  }

  // Plugin settings with the placement's instanceSettings merged on top. Objects
  // merge key by key; every other value replaces the plugin's value. The result is
  // a copy, so changing it never changes the plugin settings. `rev` is
  // PluginInstances.revision: passing it makes the caller's binding re-evaluate
  // after an instance save.
  function effectiveSettings(baseSettings, placement, rev) {
    var merged = _clone(baseSettings || {});
    var entry = entryFor(placement);
    var overrides = entry ? entry.instanceSettings : null;
    if (overrides && typeof overrides === "object")
      merged = _merge(merged, overrides);
    return merged;
  }

  function _clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function _isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function _merge(target, patch) {
    for (var key in patch) {
      if (_isObject(patch[key]) && _isObject(target[key]))
        target[key] = _merge(target[key], patch[key]);
      else
        target[key] = _clone(patch[key]);
    }
    return target;
  }

  // Writes the placement's instanceSettings (null removes the key) through the
  // write path of the list the placement lives in. Refuses when the entry there
  // no longer belongs to the plugin.
  function writeSettings(pluginKey, placement, value) {
    var entry = entryFor(placement);
    if (!entry || entry.id !== "plugin:" + pluginKey) {
      Logger.w("PluginInstances", "Placement no longer holds this plugin; instance settings not saved:", pluginKey);
      return false;
    }
    var next = Object.assign({}, entry);
    if (value)
      next.instanceSettings = value;
    else
      delete next.instanceSettings;

    if (placement.kind === "bar") {
      if (placement.list === "global") {
        // Same write as BarService.openWidgetSettings for the global list
        var row = Settings.data.bar.widgets[placement.section].slice();
        row[placement.index] = next;
        Settings.data.bar.widgets[placement.section] = row;
      } else {
        // Same write as BarService.openWidgetSettings for a screen's own list
        var overrideWidgets = _clone(Settings.getBarWidgetsForScreen(placement.list));
        overrideWidgets[placement.section][placement.index] = next;
        Settings.setScreenOverride(placement.list, "widgets", overrideWidgets);
      }
    } else if (placement.kind === "controlCenter") {
      // Same write as ControlCenterTab._updateWidgetSettingsInSection
      var shortcuts = Settings.data.controlCenter.shortcuts[placement.section].slice();
      shortcuts[placement.index] = next;
      Settings.data.controlCenter.shortcuts[placement.section] = shortcuts;
    } else if (placement.kind === "desktop") {
      // Same write as DesktopWidgetRegistry.updateWidgetData, with the key removable
      var monitors = (Settings.data.desktopWidgets.monitorWidgets || []).slice();
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name === placement.screenName) {
          var widgets = (monitors[i].widgets || []).slice();
          widgets[placement.index] = next;
          monitors[i] = Object.assign({}, monitors[i], {
                                        "widgets": widgets
                                      });
          break;
        }
      }
      Settings.data.desktopWidgets.monitorWidgets = monitors;
    } else {
      return false;
    }
    Settings.saveImmediate();
    root.revision++;
    return true;
  }
}
