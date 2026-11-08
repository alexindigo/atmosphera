pragma Singleton

import QtQuick
import Quickshell
import "../../Helpers/PluginSettingsEditor.js" as PluginSettingsEditor
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

  // Editors capture the complete owning atomic leaf, not just a repeated type
  // ID at an index. I5 maps this factory to the declared worker overlay editor.
  function _owningValue(placement) {
    if (placement.kind === "bar")
      return placement.list === "global" ? Settings.data.bar.widgets[placement.section] : Settings.data.bar.screenOverrides;
    if (placement.kind === "controlCenter")
      return Settings.data.controlCenter.shortcuts[placement.section];
    if (placement.kind === "desktop")
      return Settings.data.desktopWidgets.monitorWidgets;
    return undefined;
  }

  // Resolve one concrete list inside its owning atomic leaf. Capture this before
  // an editor opens; later callbacks must not select a newer row at the address.
  function _captureListEditor(placement) {
    if (placement.kind === "bar" && placement.list === "global")
      return Settings.createRecordListEditor(["bar", "widgets", placement.section], []);
    if (placement.kind === "controlCenter")
      return Settings.createRecordListEditor(["controlCenter", "shortcuts", placement.section], []);
    var monitors;
    var name;
    if (placement.kind === "bar") {
      monitors = Settings.data.bar.screenOverrides;
      name = placement.list;
    } else if (placement.kind === "desktop") {
      monitors = Settings.data.desktopWidgets.monitorWidgets;
      name = placement.screenName;
    } else {
      return null;
    }
    for (var i = 0; i < monitors.length; ++i) {
      if (monitors[i].name !== name)
        continue;
      if (placement.kind === "bar")
        return Settings.createRecordListEditor(["bar", "screenOverrides"], [{index: i}, {key: "widgets"}, {key: placement.section}]);
      return Settings.createRecordListEditor(["desktopWidgets", "monitorWidgets"], [{index: i}, {key: "widgets"}]);
    }
    return null;
  }

  // Old-owner binding identity ignores instance overrides but includes the owning
  // list structure. Foreign preference edits retain preview; ambiguous placement
  // replacement/reorder cannot project a patch onto another row. I5 uses native
  // normalized owner identity instead of this conservative structural fence.
  function previewBindingStamp(base, placement, rev) {
    if (!base || !placement || Service.getPluginAPI(base.pluginId) !== base)
      return null;
    var entry = entryFor(placement);
    var owner = _owningValue(placement);
    if (!entry || entry.id !== "plugin:" + base.pluginId || owner === undefined)
      return null;
    function rows(list) {
      return Array.prototype.map.call(list || [], function (row) {
        var value = Object.assign(Object.create(null), row);
        delete value.instanceSettings;
        return value;
      });
    }
    var shape;
    if (placement.kind === "controlCenter" || (placement.kind === "bar" && placement.list === "global")) {
      shape = rows(owner);
    } else {
      shape = Array.prototype.map.call(owner, function (monitor) {
        var value = Object.assign(Object.create(null), monitor);
        if (placement.kind === "desktop") {
          if (monitor.widgets) value.widgets = rows(monitor.widgets);
        } else if (monitor.widgets) {
          var sections = Object.assign(Object.create(null), monitor.widgets);
          for (var section of ["left", "center", "right"])
            if (monitor.widgets[section]) sections[section] = rows(monitor.widgets[section]);
          value.widgets = sections;
        }
        return value;
      });
    }
    return JSON.stringify([placement, shape]);
  }

  function createSettingsEditor(pluginKey, placement, base) {
    if (!base || !placement)
      return null;
    var address = _clone(placement);
    var commands = root._captureListEditor(address);
    if (!commands)
      return null;
    return PluginSettingsEditor.create({
      stamp: function () {
        var entry = root.entryFor(address);
        var owner = root._owningValue(address);
        if (Service.getPluginAPI(pluginKey) !== base || owner === undefined || !entry || entry.id !== "plugin:" + pluginKey)
          return null;
        return JSON.stringify([base.pluginSettings, owner]);
      },
      value: function () { return root.effectiveSettings(base.pluginSettings, address, root.revision); },
      later: function (callback) { Qt.callLater(callback); },
      commit: function (value, reset, callback) {
        if (!reset && (value === null || typeof value !== "object" || Array.isArray(value))) {
          Qt.callLater(function () { callback({status: "failed", error: {code: "editor-input"}}); });
          return false;
        }
        // Keep the old owner's existing sparse policy here, not in the reusable
        // popup. The worker owns this merge/difference operation after I5.
        var changed = {};
        if (!reset) {
          var shared = base.pluginSettings || {};
          for (var key in value) {
            if (JSON.stringify(value[key]) !== JSON.stringify(shared[key]))
              changed[key] = root._clone(value[key]);
          }
        }
        return root.writeSettings(pluginKey, address, Object.keys(changed).length ? changed : null, callback, commands);
      }
    });
  }

  // Writes the placement's instanceSettings (null removes the key) through the
  // write path of the list the placement lives in. Refuses when the entry there
  // no longer belongs to the plugin.
  function writeSettings(pluginKey, placement, value, callback, capturedCommands) {
    var entry = entryFor(placement);
    if (!entry || entry.id !== "plugin:" + pluginKey) {
      Logger.w("PluginInstances", "Placement no longer holds this plugin; instance settings not saved:", pluginKey);
      Qt.callLater(function () {
        if (typeof callback === "function")
          callback({status: "failed", error: {code: "plugin-placement"}});
      });
      return false;
    }
    // Runtime views capture at the immediate command boundary; delayed editors
    // pass the original session. Every placement route submits only the explicit
    // instanceSettings field intent, never a normalized display-row replacement.
    var commands = capturedCommands || root._captureListEditor(placement);
    if (!commands) {
      Qt.callLater(function () {
        if (typeof callback === "function")
          callback({status: "failed", error: {code: "plugin-placement"}});
      });
      return false;
    }
    var edit = {op: value === null ? "unset" : "set", index: placement.index, field: "instanceSettings"};
    if (value !== null)
      edit.value = value;
    var accepted = commands.submit([edit], function (result) {
      if (result.status !== "admitted" || result.refreshState !== "current") {
        if (typeof callback === "function")
          callback({status: "failed", error: result.error || {code: "list-edit-conflict"}});
        return;
      }
      Settings.saveResult(callback);
    });
    if (accepted)
      root.revision++;
    return accepted;
  }
}
