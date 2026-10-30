// Inert owner-factory witness. Popup/page API staging is a separate I4 boundary.
import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

Scope {
  id: root
  property bool started: false
  property var api: null
  property string key: "i4-editors"
  property var placements: [
    {
      kind: "bar",
      list: "global",
      section: "left",
      index: 0
    },
    {
      kind: "bar",
      list: "I4-screen",
      section: "left",
      index: 0
    },
    {
      kind: "controlCenter",
      section: "left",
      index: 0
    },
    {
      kind: "desktop",
      screenName: "I4-screen",
      index: 0
    }
  ]
  property var names: ["global-saved", "screen-saved", "control-saved", "desktop-saved"]
  property string globalConsumer: PluginInstances.effectiveSettings(api ? api.pluginSettings : {}, placements[0], PluginInstances.revision).label || ""
  property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"

  function check(ok, label) {
    if (!ok)
      throw new Error("I4_PLUGIN_EDITORS_ASSERT: " + label);
  }
  function guard(fn) {
    try {
      fn();
    } catch (error) {
      console.error(String(error));
      Qt.exit(2);
    }
  }
  function row(tag) {
    return {
      id: "plugin:" + key,
      tag: tag,
      instanceSettings: {
        label: "original",
        opaque: {
          keep: true
        }
      }
    };
  }
  function register(value) {
    api = Service.createPluginAPI(key, {
                                    metadata: {}
                                  }, value, {}, {}, {});
    var plugins = Object.assign({}, Service.loadedPlugins);
    plugins[key] = {
      api: api
    };
    Service.loadedPlugins = plugins;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    if (verifyOnly) {
      Service.loadPluginSettings(key, function (value) {
        root.guard(function () {
          root.register(value);
          root.finalChecks();
          console.log("I4_PLUGIN_EDITORS: RESTART_PASS");
          Qt.exit(0);
        });
      });
      return;
    }
    guard(function () {
      register({
                 label: "shared",
                 nested: {
                   base: true
                 }
               });
      Settings.data.bar.widgets.left = [row("first"), row("second")];
      Settings.data.bar.screenOverrides = [
            {
              name: "I4-screen",
              opaque: "monitor",
              widgets: {
                left: [row("screen")],
                center: [],
                right: []
              }
            }
          ];
      Settings.data.controlCenter.shortcuts.left = [row("control")];
      Settings.data.desktopWidgets.monitorWidgets = [
            {
              name: "I4-screen",
              opaque: "desktop-monitor",
              widgets: [row("desktop")]
            }
          ];
      Settings.saveResult(function (result) {
        root.guard(function () {
          root.check(result.status === "saved", "baseline save");
          root.cancelAndShared();
        });
      });
    });
  }
  function cancelAndShared() {
    var cancelled = api.createSettingsEditor();
    check(cancelled && cancelled.initialValue.label === "shared", "shared factory");
    cancelled.initialValue.nested.base = false;
    check(api.pluginSettings.nested.base && cancelled.discard(), "detached Cancel no live mutation");
    var editor = api.createSettingsEditor();
    var submitted = editor.initialValue;
    submitted.label = "shared-saved";
    editor.apply(submitted, function (result) {
      root.guard(function () {
        root.check(result.status === "saved" && result.refreshState === "current", "shared acknowledged Apply");
        root.check(root.api.pluginSettings.label === "shared-saved" && root.api.pluginSettings.nested.base, "shared actual consumer");
        root.staleRefresh();
      });
    });
    submitted.nested.base = false;
  }
  function staleRefresh() {
    var editor = api.createSettingsEditor();
    editor.apply({
                   label: "submitted-stale",
                   nested: {
                     base: true
                   }
                 }, function (result) {
                   root.guard(function () {
                     root.check(result.status === "saved" && result.refreshState === "stale", "post-admission change keeps truthful save and stale refresh");
                     root.check(root.api.pluginSettings.label === "later-preview", "older save does not overwrite newer API input");
                     var current = root.api.createSettingsEditor();
                     current.apply({
                                     label: "shared-saved",
                                     nested: {
                                       base: true
                                     }
                                   }, function (saved) {
                                     root.guard(function () {
                                       root.check(saved.status === "saved" && saved.refreshState === "current", "explicit current editor resolves newer preview");
                                       root.placementConflict();
                                     });
                                   });
                   });
                 });
    api.pluginSettings = {
      label: "later-preview",
      nested: {
        base: true
      }
    };
  }
  function placementConflict() {
    var editor = PluginInstances.createSettingsEditor(key, placements[0], api);
    var before = Settings.data.bar.widgets.left.slice();
    Settings.data.bar.widgets.left = [before[1], before[0]];
    var value = editor.initialValue;
    value.label = "must not overwrite repeated ID";
    editor.apply(value, function (result) {
      root.guard(function () {
        root.check(result.status === "failed" && result.error.code === "editor-conflict", "whole-leaf fence rejects repeated-ID reorder");
        root.check(Settings.data.bar.widgets.left[0].tag === "second" && Settings.data.bar.widgets.left[0].instanceSettings.label === "original", "replacement row preserved");
        Settings.data.bar.widgets.left = before;
        root.baseConflict();
      });
    });
  }
  function baseConflict() {
    var editor = PluginInstances.createSettingsEditor(key, placements[1], api);
    api.pluginSettings = {
      label: "foreign",
      nested: {
        base: true
      }
    };
    editor.apply(editor.initialValue, function (result) {
      root.guard(function () {
        root.check(result.status === "failed" && result.error.code === "editor-conflict", "shared-base fence");
        root.api.pluginSettings = {
          label: "shared-saved",
          nested: {
            base: true
          }
        };
        root.unloadConflict();
      });
    });
  }
  function unloadConflict() {
    var editor = PluginInstances.createSettingsEditor(key, placements[2], api);
    var original = Service.loadedPlugins;
    var plugins = Object.assign({}, original);
    delete plugins[key];
    Service.loadedPlugins = plugins;
    editor.apply(editor.initialValue, function (result) {
      root.guard(function () {
        root.check(result.status === "failed", "base unload refuses stale handle");
        Service.loadedPlugins = original;
        root.failureRetry();
      });
    });
  }
  function failureRetry() {
    var editor = PluginInstances.createSettingsEditor(key, placements[0], api);
    var value = editor.initialValue;
    value.label = names[0];
    Settings.setBindingsUnresolved(true);
    editor.apply(value, function (failed) {
      root.guard(function () {
        root.check(failed.status === "failed" && failed.refreshState === "not_refreshed", "failed real save does not refresh");
        root.check(root.globalConsumer === root.names[0], "old-owner admitted preview remains live after failure");
        Settings.setBindingsUnresolved(false);
        editor.apply(value, function (result) {
          root.guard(function () {
            root.check((result.status === "saved" || result.status === "nothing_to_save") && result.refreshState === "current", "retry own admitted input: " + result.status + "/" + (result.error ? result.error.code : ""));
            root.applyPlacement(1);
          });
        });
      });
    });
  }
  function applyPlacement(index) {
    if (index === placements.length) {
      var reset = PluginInstances.createSettingsEditor(key, placements[3], api);
      reset.resetOverrides(function (result) {
        root.guard(function () {
          root.check(result.status === "saved" && result.refreshState === "current", "acknowledged instance reset");
          root.finalChecks();
          console.log("I4_PLUGIN_EDITORS: SAVED_PASS");
          Qt.exit(0);
        });
      });
      return;
    }
    var editor = PluginInstances.createSettingsEditor(key, placements[index], api);
    check(editor !== null, "placement factory " + index);
    var value = editor.initialValue;
    value.label = names[index];
    editor.apply(value, function (result) {
      root.guard(function () {
        root.check(result.status === "saved" && result.refreshState === "current", "placement receipt " + index);
        root.applyPlacement(index + 1);
      });
    });
  }
  function finalChecks() {
    check(api.pluginSettings.label === "shared-saved" && api.pluginSettings.nested.base, "shared restarted value");
    for (var i = 0; i < 3; i++) {
      var entry = PluginInstances.entryFor(placements[i]);
      var effective = PluginInstances.effectiveSettings(api.pluginSettings, placements[i], PluginInstances.revision);
      check(effective.label === names[i] && effective.nested.base && entry.instanceSettings.opaque.keep, "instance consumer and opaque override " + i);
      check(entry.instanceSettings.nested === undefined, "equal base omitted " + i);
    }
    check(globalConsumer === names[0] && Settings.data.bar.widgets.left[1].tag === "second", "reactive global and repeated sibling");
    check(PluginInstances.entryFor(placements[3]).instanceSettings === undefined, "reset removes override field");
    check(PluginInstances.effectiveSettings(api.pluginSettings, placements[3], PluginInstances.revision).label === "shared-saved", "reset consumer inherits base");
    check(Settings.data.bar.screenOverrides[0].opaque === "monitor" && Settings.data.desktopWidgets.monitorWidgets[0].opaque === "desktop-monitor", "unknown owner fields preserved");
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 180000
    running: true
    onTriggered: {
      console.error("I4_PLUGIN_EDITORS_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
