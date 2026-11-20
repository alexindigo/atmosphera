// Preparatory native field capability witness, not generic-page adoption proof.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  property var api: null
  property var selected: null
  property var sibling: null
  property var editor: null
  property var fields: null
  property var flagHandle: null
  property var afterRuntimeRefresh: null
  property string phase: "opening"
  readonly property bool cold: Quickshell.env("PHA_FIELDS_COLD") === "1"
  readonly property string family: Quickshell.env("PHA_FIELDS_FAMILY") || "desktop"
  readonly property var placement: family === "global-bar" ? ({
                                                                kind: "bar",
                                                                list: "global",
                                                                section: "left",
                                                                index: 0
                                                              }) : family === "monitor-bar" ? ({
                                                                                                 kind: "bar",
                                                                                                 list: Quickshell.screens[0].name,
                                                                                                 section: "left",
                                                                                                 index: 0
                                                                                               }) : family === "control-center" ? ({
                                                                                                                                     kind: "controlCenter",
                                                                                                                                     section: "left",
                                                                                                                                     index: 0
                                                                                                                                   }) : ({
                                                                                                                                           kind: "desktop",
                                                                                                                                           screenName: Quickshell.screens[0].name,
                                                                                                                                           index: 0
                                                                                                                                         })
  readonly property var legacy: ({
                                   todos: [
                                     {
                                       id: 91,
                                       text: "legacy instance task",
                                       completed: false,
                                       pageId: 0,
                                       priority: "medium",
                                       details: ""
                                     }
                                   ],
                                   pages: [
                                     {
                                       id: 0,
                                       name: "Legacy"
                                     }
                                   ],
                                   current_page_id: 0,
                                   count: 1,
                                   completedCount: 0,
                                   opaque: {
                                     keep: "legacy"
                                   }
                                 })

  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
    printErrors: false
  }
  Component {
    id: fieldsFactory
    PluginSettingsFields {}
  }
  Text {
    id: presentation
    text: root.flagHandle ? String(root.flagHandle.value) : "opening"
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("FIELDS_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function protectedValues() {
    check(api.pluginSettings.todos.length === 2 && api.pluginSettings.pages.length === 2, "shared content unchanged");
    check(selected.pluginSettings.todos.length === 1 && selected.pluginSettings.todos[0].id === 91, "legacy instance task retained");
    check(selected.pluginSettings.pages[0].name === "Legacy" && selected.pluginSettings.count === 1, "legacy pages/counter retained");
    check(sibling.pluginSettings.todos.length === 2, "sibling still sees shared content");
  }
  function apply(next) {
    editor.apply(editor.values, function (result) {
      try {
        check(["saved", "nothing_to_save"].indexOf(result.status) !== -1 && result.refreshState === "current", "accepted native Apply");
        check(fields.acknowledge(result), "read facts recaptured only after current Apply");
        protectedValues();
        // The selected live overlay refresh is a separate native subscription,
        // not the editor's receipt. Observe its final values before continuing.
        afterRuntimeRefresh = next;
        phase = "refresh";
      } catch (error) {
        fail(error);
      }
    });
  }
  function opened() {
    editor = selected.createSettingsEditor(true);
    check(editor !== null, "captured instance editor created");
    editor.whenReady(function (result) {
      try {
        check(result.status === "opened" && editor.fieldCapture.current(), "native and read facts share capture");
        fields = fieldsFactory.createObject(root, {
                                              editor: editor,
                                              scopeKind: "instance",
                                              metadata: api.settingsOwner.store.settingsEditorMetadata,
                                              capture: editor.fieldCapture,
                                              recapture: function () {
                                                return PluginInstances.captureSettingsFields(root.api, root.placement);
                                              }
                                            });
        check(fields && fields.ready && !editor.dirty, "construction submits no intent");
        var flag = fields.field("showCompleted");
        flagHandle = flag;
        check(flag === fields.field("showCompleted") && flag.handle === undefined && flag.editor === undefined, "stable limited handle");
        check(flag.value === false && flag.inheritedValue === true && flag.overridden && flag.pendingIntent === "", "captured inherited/overridden state");
        var colors = fields.field("priorityColors").value;
        colors.high = "foreign projection edit";
        check(editor.values.priorityColors.high !== colors.high && !editor.dirty, "compound read cannot publish through alias");
        // A separate capability object checks rejection without clearing that
        // rejected page's error to manufacture an acknowledged save.
        var rejected = fieldsFactory.createObject(root, {
                                                    editor: editor,
                                                    scopeKind: "instance",
                                                    metadata: api.settingsOwner.store.settingsEditorMetadata,
                                                    capture: editor.fieldCapture,
                                                    recapture: function () {
                                                      return null;
                                                    }
                                                  });
        for (var key of ["todos", "pages", "current_page_id", "count", "completedCount", "undeclared"])
          check(rejected.field(key) === null, "nonconfiguration field denied: " + key);
        check(rejected.contentField("todos") === null && rejected.error !== "", "instance cannot obtain shared content writer");
        check(!rejected.resetFields(["showCompleted", "todos"]), "multi-field Reset validates every capability before any native edit");
        check(!editor.dirty, "denied capabilities did not create native intent");
        rejected.destroy();
        check(flag.reset() && flag.pendingIntent === "reset" && flag.value === true && flag.overridden, "Reset presents captured inheritance before receipt");
        var captured = fields.capture;
        check(!fields.acknowledge({
                                    status: "failed",
                                    refreshState: "not_refreshed"
                                  }) && fields.capture === captured && flag.pendingIntent === "reset", "failure retains intent and read capture");
        check(!fields.acknowledge({
                                    status: "saved",
                                    refreshState: "stale"
                                  }) && fields.capture === captured && flag.pendingIntent === "reset", "stale success cannot recapture");
        apply(function () {
          check(!flag.overridden && flag.pendingIntent === "" && flag.value === true, "field override removed on current receipt");
          check(PluginInstances.entryFor(placement).instanceSettings.showBackground === false, "unrelated override preserved");
          check(flag.set(false) && flag.value === false && !flag.overridden && flag.pendingIntent === "set", "explicit false is intent, not stored metadata");
          apply(function () {
            check(flag.overridden && selected.pluginSettings.showCompleted === false && sibling.pluginSettings.showCompleted === true, "only selected instance changed: " + JSON.stringify({
                                                                                                                                                                                             overridden: flag.overridden,
                                                                                                                                                                                             selected: selected.pluginSettings.showCompleted,
                                                                                                                                                                                             sibling: sibling.pluginSettings.showCompleted
                                                                                                                                                                                           }));
            check(flag.set(true), "explicit equal-value set admitted");
            apply(function () {
              check(!flag.overridden, "native top-level equal omission remains owner");
              check(fields.field("exportPath").set(""), "explicit empty String accepted");
              apply(function () {
                check(selected.pluginSettings.exportPath === "", "empty value reaches runtime consumer");
                check(fields.resetFields(["exportPath", "showBackground"]), "multi-field Reset submits separate native atomic paths");
                check(fields.field("exportPath").pendingIntent === "reset" && fields.field("showBackground").pendingIntent === "reset", "both requested fields retain reset intent");
                apply(function () {
                  check(!Object.prototype.hasOwnProperty.call(PluginInstances.entryFor(placement).instanceSettings, "exportPath") && !Object.prototype.hasOwnProperty.call(PluginInstances.entryFor(placement).instanceSettings, "showBackground"), "multi-field native removal persisted");
                  fields.resetConfiguration(function (receipt) {
                    try {
                      check(receipt.status !== "failed" && receipt.refreshState === "current" && fields.acknowledge(receipt), "whole configuration Reset acknowledged");
                      for (var key of fields.configurationKeys)
                        check(!Object.prototype.hasOwnProperty.call(PluginInstances.entryFor(placement).instanceSettings, key), "configuration override removed: " + key);
                      check(PluginInstances.entryFor(placement).instanceSettings.opaque.keep === "legacy", "opaque sibling preserved");
                      protectedValues();
                      phase = "rendered";
                    } catch (error) {
                      fail(error);
                    }
                  });
                });
              });
            });
          });
        });
      } catch (error) {
        fail(error);
      }
    });
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      todo: manifest
    };
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "real native Todo owner opened");
        api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          todo: {
            api: api
          }
        };
        function runtimes() {
          selected = PluginInstances.apiFor("todo", placement);
          sibling = PluginInstances.apiFor("todo", Object.assign({}, placement, {
                                                                   index: 1
                                                                 }));
          phase = "runtimes";
        }
        if (cold) {
          runtimes();
          return;
        }
        var rows = [
              {
                id: "plugin:todo",
                instanceSettings: Object.assign({}, legacy, {
                                                  showCompleted: false,
                                                  showBackground: false,
                                                  isExpanded: false
                                                })
              },
              {
                id: "plugin:todo"
              }
            ];
        var owningPath;
        if (family === "global-bar") {
          Settings.data.bar.widgets.left = rows;
          owningPath = ["bar", "widgets", "left"];
        } else if (family === "monitor-bar") {
          Settings.data.bar.screenOverrides = [
                {
                  name: Quickshell.screens[0].name,
                  widgets: {
                    left: rows,
                    center: [],
                    right: []
                  }
                }
              ];
          owningPath = ["bar", "screenOverrides"];
        } else if (family === "control-center") {
          Settings.data.controlCenter.shortcuts.left = rows;
          owningPath = ["controlCenter", "shortcuts", "left"];
        } else {
          check(family === "desktop", "known placement family");
          Settings.data.desktopWidgets.monitorWidgets = [
                {
                  name: placement.screenName,
                  widgets: rows
                }
              ];
          owningPath = ["desktopWidgets", "monitorWidgets"];
        }
        Settings.saveSelected([owningPath], function (receipt) {
          try {
            check(receipt.status !== "failed", "fixture placement persisted");
            runtimes();
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      try {
        if (phase === "runtimes" && selected.settingsReady && sibling.settingsReady) {
          protectedValues();
          if (cold) {
            check(selected.pluginSettings.showCompleted === true && selected.pluginSettings.showBackground === true, "separate cold instance inherits");
            console.log("PLUGIN_SETTINGS_FIELDS: COLD_PASS");
            Qt.exit(0);
            return;
          }
          phase = "editor";
          opened();
        } else if (phase === "refresh" && fields.configurationKeys.every(function (key) {
          return JSON.stringify(selected.pluginSettings[key]) === JSON.stringify(fields.field(key).value);
        })) {
          var next = afterRuntimeRefresh;
          afterRuntimeRefresh = null;
          phase = "editor";
          next();
        } else if (phase === "rendered" && presentation.text === "true") {
          check(!editor.dirty, "no residual native intent after current reset");
          editor.discard();
          console.log("PLUGIN_SETTINGS_FIELDS: NATIVE_OPERATIONS_COMPLETE (independent file and cold gates still required)");
          Qt.exit(0);
        }
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("native fields watchdog at " + root.phase)
  }
  Component.onCompleted: begin()
}
