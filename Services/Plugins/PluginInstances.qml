pragma Singleton
import ConfigQml 1.0
import QtQuick
import Quickshell
import "../../Helpers/SettingsListCommands.js" as Lists
import qs.Commons
import qs.Services.Plugins

// Placement addressing and handle lifetime only. Native overlays own live
// values, sparse differences, row mapping, revisions and persistence.
Singleton {
  id: root
  property var _cache: Object.create(null)
  property real _spawnSequence: 0
  property int invocationRevision: 0
  // Presentation invalidation only; never a capture/conflict generation.
  property int revision: 0
  Component {
    id: apiFactory
    PluginInstanceApi {}
  }
  Component {
    id: editorFactory
    PluginPreferenceEditor {}
  }
  // Retirement owns cache destruction. Entry points can already be using
  // the new generation's APIs when Service announces pluginLoaded.
  Connections {
    target: Settings
    function onEffectiveSettingsChanged(section) {
      if (["bar", "controlCenter", "desktopWidgets"].indexOf(section) !== -1)
        root.revision++;
    }
  }
  function barList(screenName) {
    return !screenName || Settings.getBarWidgetsForScreen(screenName) === Settings.data.bar.widgets ? "global" : screenName;
  }
  function apiFor(pluginKey, placement) {
    void root.revision;
    var base = Service.getPluginAPI(pluginKey);
    if (!base || !placement)
      return null;
    var key = JSON.stringify([pluginKey, placement]);
    var cached = _cache[key];
    if (cached && cached.base === base && !cached.api.settingsError)
      return cached.api;
    if (cached)
      cached.api.destroy();
    var api = apiFactory.createObject(root, {
                                        base: base,
                                        placement: Lists.copy(placement)
                                      });
    _cache[key] = {
      base: base,
      api: api,
      sequence: 0
    };
    invocationRevision++;
    return api;
  }
  function _recordFor(api) {
    if (!api)
      return null;
    var record = _cache[JSON.stringify([api.pluginId, api.placement])];
    return record?.api === api ? record : null;
  }
  function noteSpawnedView(api) {
    var record = _recordFor(api);
    if (!record || record.sequence !== 0)
      return;
    record.sequence = ++_spawnSequence;
    invocationRevision++;
  }
  function ownsInvocationApi(base, api) {
    return !!(_recordFor(api) && api.base === base && !api.settingsError && (!api.placement || entryFor(api.placement)?.id === "plugin:" + api.pluginId));
  }
  // A control center entry survives dismissing its container. A placement
  // remains live while its native mapping is current, not while it is drawn.
  // Looking at placement settings alone does not spawn a placed instance.
  function latestInvocationApi(base) {
    void invocationRevision;
    void revision;
    var newest = null;
    for (var record of Object.values(_cache)) {
      if (!record.sequence || record.base !== base || !ownsInvocationApi(base, record.api))
        continue;
      if (!newest || record.sequence > newest.sequence)
        newest = record;
    }
    return newest?.api ?? null;
  }
  function createInvocationApi(base) {
    var key = JSON.stringify([base.pluginId, null]);
    var cached = _cache[key];
    if (cached?.base === base)
      return cached.api;
    var api = apiFactory.createObject(root, {
                                        base: base
                                      });
    _cache[key] = {
      base: base,
      api: api,
      sequence: ++_spawnSequence
    };
    invocationRevision++;
    return api;
  }
  function _dropPlugin(pluginKey, callback) {
    var pending = 0;
    var complete = false;
    function released() {
      pending--;
      if (complete && pending === 0 && typeof callback === "function")
        Qt.callLater(callback);
    }
    for (var key of Object.keys(_cache)) {
      if (_cache[key].base.pluginId === pluginKey) {
        pending++;
        _cache[key].api.Component.destruction.connect(released);
        _cache[key].api.destroy();
        delete _cache[key];
      }
    }
    revision++;
    invocationRevision++;
    complete = true;
    if (pending === 0 && typeof callback === "function")
      Qt.callLater(callback);
  }
  function settlePlugin(pluginKey, callback, retry) {
    var apis = Object.keys(_cache).filter(function (key) {
      return root._cache[key].base.pluginId === pluginKey;
    }).map(function (key) {
      return root._cache[key].api;
    });
    function next(index) {
      if (index === apis.length) {
        root._dropPlugin(pluginKey, function () {
          callback({
                     status: "nothing_to_save"
                   });
        });
        return;
      }
      Service.waitForPluginSaves(apis[index], function (result) {
        if (result.status === "failed")
          callback(result);
        else
          next(index + 1);
      }, retry);
    }
    next(0);
  }
  function address(placement) {
    if (!placement || !Number.isSafeInteger(placement.index) || placement.index < 0)
      return null;
    var result;
    if (placement.kind === "bar" && placement.list === "global" && ["left", "center", "right"].indexOf(placement.section) !== -1)
      return {
        path: ["bar", "widgets", placement.section],
        entry: [
          {
            index: placement.index
          }
        ]
      };
    if (placement.kind === "controlCenter" && ["left", "right"].indexOf(placement.section) !== -1)
      return {
        path: ["controlCenter", "shortcuts", placement.section],
        entry: [
          {
            index: placement.index
          }
        ]
      };
    var monitors;
    var name;
    if (placement.kind === "bar" && ["left", "center", "right"].indexOf(placement.section) !== -1) {
      monitors = Settings.data.bar.screenOverrides;
      name = placement.list;
      result = {
        path: ["bar", "screenOverrides"],
        entry: []
      };
    } else if (placement.kind === "desktop") {
      monitors = Settings.data.desktopWidgets.monitorWidgets;
      name = placement.screenName;
      result = {
        path: ["desktopWidgets", "monitorWidgets"],
        entry: []
      };
    } else
      return null;
    for (var i = 0; i < monitors.length; ++i) {
      if (monitors[i].name !== name)
        continue;
      result.entry = [
            {
              index: i
            },
            {
              key: "widgets"
            }
          ];
      if (placement.kind === "bar")
        result.entry.push({
                            key: placement.section
                          });
      result.entry.push({
                          index: placement.index
                        });
      return result;
    }
    return null;
  }
  function entryFor(placement) {
    var selected = address(placement);
    if (!selected)
      return null;
    var value = Settings.data;
    for (var segment of selected.path)
      value = value[segment];
    for (var selector of selected.entry) {
      if (value === null || value === undefined)
        return null;
      value = Object.prototype.hasOwnProperty.call(selector, "index") ? value[selector.index] : value[selector.key];
    }
    return value || null;
  }
  // Read facts only: no values here are later submitted to a writer. Capture
  // the same displayed leaf generation and settled base that openOverlay uses.
  function captureSettingsFields(base, placement) {
    var selected = address(placement);
    var scope = base ? base.settingsHandle : null;
    if (!selected || !scope || !base.settingsOwner || base.settingsOwner.closed || Service.getPluginAPI(base.pluginId) !== base)
      return null;
    var main = Settings.store;
    var ownerInfo = main.info(selected.path);
    if (!Lists.settled(ownerInfo))
      return null;
    var entry = entryFor(placement);
    if (!entry || entry.id !== "plugin:" + base.pluginId)
      return null;
    var fields = Object.create(null);
    var generations = Object.create(null);
    var overrides = entry.instanceSettings || Object.create(null);
    for (var key of base.settingsOwner.store.settingsKeys) {
      var info = scope.info([key]);
      if (!Lists.settled(info))
        return null;
      generations[key] = info.publicationGeneration;
      fields[key] = {
        inheritedPresent: info.present,
        overridden: Object.prototype.hasOwnProperty.call(overrides, key)
      };
      if (info.present)
        fields[key].inheritedValue = main.copyValue(scope.values[key]);
    }
    return {
      fields: fields,
      current: function () {
        return Service.getPluginAPI(base.pluginId) === base && !base.settingsOwner.closed && main.info(selected.path).publicationGeneration === ownerInfo.publicationGeneration && Lists.settled(main.info(selected.path)) && Object.keys(generations).every(function (key) {
          var now = scope.info([key]);
          return Lists.settled(now) && now.publicationGeneration === generations[key];
        });
      }
    };
  }
  function _open(base, placement, mode, callback, previewBase, captureFields) {
    var active = true;
    var submitted = false;
    var scope = previewBase || (base ? base.settingsHandle : null);
    var main = Settings.store;
    // A placement belongs to the displayed publication at the request boundary.
    // Waiting for settled input must not recapture a different row at this index.
    var selected = address(placement);
    var ownerGeneration = selected ? main.info(selected.path).publicationGeneration : null;
    function disconnect() {
      main.completed.disconnect(attempt);
      main.statusChanged.disconnect(attempt);
      Service.pluginLoaded.disconnect(attempt);
      Service.pluginUnloaded.disconnect(attempt);
      if (scope) {
        scope.completed.disconnect(attempt);
        scope.statusChanged.disconnect(attempt);
      }
    }
    function attempt() {
      if (!active || submitted)
        return;
      if (!scope || Service.getPluginAPI(base.pluginId) !== base || !base.settingsOwner || base.settingsOwner.closed) {
        active = false;
        disconnect();
        callback({
                   status: "failed",
                   error: {
                     code: "overlay-owner"
                   }
                 });
        return;
      }
      if (main.status === ConfigStore.Error || main.status === ConfigStore.Closed || main.status === ConfigStore.Closing || scope.status === ConfigStore.Error || scope.status === ConfigStore.Closed || scope.status === ConfigStore.Closing) {
        active = false;
        disconnect();
        callback({
                   status: "failed",
                   error: {
                     code: "overlay-owner"
                   }
                 });
        return;
      }
      if (!main.ready)
        return;
      if (!selected) {
        active = false;
        disconnect();
        callback({
                   status: "failed",
                   error: {
                     code: "overlay-identity"
                   }
                 });
        return;
      }
      if (!Lists.settled(main.info(selected.path)) || !base.settingsOwner.store.settingsKeys.every(function (key) {
        return Lists.settled(scope.info([key]));
      }))
        return;
      if (main.info(selected.path).publicationGeneration !== ownerGeneration) {
        active = false;
        disconnect();
        callback({
                   status: "failed",
                   error: {
                     code: "overlay-identity"
                   }
                 });
        return;
      }
      submitted = true;
      disconnect();
      var capture = captureFields ? captureSettingsFields(base, placement) : null;
      if (captureFields && !capture) {
        active = false;
        callback({
                   status: "failed",
                   error: {
                     code: "settings-field-capture"
                   }
                 });
        return;
      }
      main.openOverlay({
                         mode: mode,
                         base: scope,
                         ownerPath: selected.path,
                         ownerGeneration: ownerGeneration,
                         entryPath: selected.entry,
                         identityPath: [
                           {
                             key: "id"
                           }
                         ],
                         identityValue: "plugin:" + base.pluginId,
                         overrideKey: "instanceSettings",
                         mergePolicy: "recursive_objects_replace_lists",
                         differencePolicy: "top_level_omit_equal"
                       }, function (result) {
                         if (!active) {
                           if (result.editor)
                             result.editor.detach();
                           return;
                         }
                         active = false;
                         if (result.status === "opened" && captureFields) {
                           if (!capture.current()) {
                             result.editor.detach();
                             callback({
                                        status: "failed",
                                        error: {
                                          code: "settings-field-capture"
                                        }
                                      });
                             return;
                           }
                           result.fieldCapture = capture;
                         }
                         callback(result);
                       });
    }
    main.completed.connect(attempt);
    main.statusChanged.connect(attempt);
    Service.pluginLoaded.connect(attempt);
    Service.pluginUnloaded.connect(attempt);
    if (scope) {
      scope.completed.connect(attempt);
      scope.statusChanged.connect(attempt);
    }
    Qt.callLater(attempt);
    return function () {
      if (active) {
        active = false;
        if (!submitted)
          disconnect();
      }
    };
  }
  function openRuntime(base, placement, callback) {
    return _open(base, Lists.copy(placement), "live", callback);
  }
  function openPreviewView(base, placement, scope, callback) {
    return _open(base, Lists.copy(placement), "view", callback, scope);
  }
  function createSettingsEditor(pluginKey, placement, base, fieldIntent) {
    if (!base || !base.settingsOwner || base.settingsOwner.closed || !placement || Service.getPluginAPI(pluginKey) !== base)
      return null;
    var editor = editorFactory.createObject(root, {
                                              fields: base.settingsOwner.store.settingsKeys
                                            });
    Service.retainPluginEditor(editor, base);
    var lifetime = editor._lifetime;
    editor.cancelOpen = _open(base, Lists.copy(placement), "editor", function (result) {
      if (!lifetime.alive || editor.closed) {
        if (result.editor)
          result.editor.detach();
        return;
      }
      if (result.status === "opened") {
        editor.fieldCapture = result.fieldCapture || null;
        editor.attach(result.editor);
      } else
        editor.openError = result.error?.code || "overlay-open";
    }, null, fieldIntent === true);
    return editor;
  }
}
