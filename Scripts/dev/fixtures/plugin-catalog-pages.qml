// Inert actual-catalog pages on the old owner. Driver supplies owned local copies.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Services.Plugins
import qs.Services.System
import qs.Widgets

ShellRoot {
  id: root
  property var cases: []
  property int index: 0
  property var api: null
  property var manifest: null
  property var held: null
  property var release: null
  property bool started: false
  property bool makeStale: false
  property int applies: 0
  readonly property var placement: ({
                                      kind: "bar",
                                      list: "global",
                                      section: "left",
                                      index: 0
                                    })
  property string phase: "start"
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property bool mainOnly: Quickshell.env("I4_MAIN_SCOPE_ONLY") === "1"
  readonly property var mainPlacement: ({
                                          kind: "bar",
                                          list: "global",
                                          section: "left",
                                          index: 1
                                        })

  FileView {
    id: inputs
    path: Quickshell.env("I4_CATALOG_INPUTS")
    blockLoading: true
    printErrors: false
  }

  function check(ok, label) {
    if (!ok)
      throw new Error("I4_CATALOG_ASSERT: " + label);
  }

  function page(): var {
    return popup.settingsPage;
  }

  function numericInput(item): var {
    if (typeof item.insert === "function" && item.validator)
      return item;
    var nested = item.children || [];
    for (var i = 0; i < nested.length; i++) {
      var input = numericInput(nested[i]);
      if (input)
        return input;
    }
    return null;
  }

  function register(item) {
    manifest = item.manifest;
    api = Service.createPluginAPI(manifest.id, manifest, {
                                    opaque: {
                                      keep: true
                                    }
                                  }, {}, {}, {});
    var plugins = Object.assign({}, Service.loadedPlugins);
    plugins[manifest.id] = {
      api: api
    };
    Service.loadedPlugins = plugins;
    if (manifest.id === "catwalk")
      createMain(api);
    var original = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = original();
      var wrapper = {
        initialValue: editor.initialValue,
        discard: editor.discard,
        apply: function (value, callback) {
          root.applies++;
          editor.apply(value, function (result) {
            root.held = result;
            root.release = function () {
              if (result.refreshState === "current")
                wrapper.initialValue = editor.initialValue;
              callback(result);
            };
          });
          if (root.makeStale) {
            var newer = Object.assign({}, root.api.pluginSettings);
            newer.message = "foreign-live";
            root.api.pluginSettings = newer;
          }
        }
      };
      return wrapper;
    };
  }

  function createMain(base) {
    var component = Qt.createComponent("file://" + Registry.getPluginDir("catwalk") + "/Main.qml");
    check(component.status === Component.Ready, "actual Catwalk Main component");
    var main = component.createObject(root, {
                                        pluginApi: base
                                      });
    check(main !== null, "actual Catwalk Main created");
    base.mainInstance = main;
  }

  function openMainInstance() {
    var item = cases.filter(function (value) {
      return value.manifest.id === "catwalk";
    })[0];
    check(item !== undefined, "Main-derived family declared");
    manifest = item.manifest;
    api = Service.getPluginAPI("catwalk");
    if (!api)
      register(item);
    var rows = mainOnly ? [] : Settings.data.bar.widgets.left.slice();
    if (rows.length === 0)
      rows.push({
                  id: "Volume"
                });
    check(rows.length === 1, "selected-instance fixture owns exactly one preceding row");
    rows.push({
                id: "plugin:catwalk",
                opaque: "main-placement",
                instanceSettings: {
                  minimumThreshold: 17,
                  hideBackground: false
                }
              });
    Settings.data.bar.widgets.left = rows;
    popup.openInstanceSettings(manifest, PluginInstances.apiFor("catwalk", mainPlacement), "settings");
    phase = "main-instance";
  }

  function deliver() {
    console.log("I4_CATALOG_RELEASE", manifest.id, held.status, held.refreshState);
    var callback = release;
    release = null;
    held = null;
    callback();
  }

  function verifyNext() {
    if (index === cases.length) {
      Service.loadPluginSettings("i4-catalog-fail", function (value) {
        try {
          root.check(value.message === "failure-newer" && value.opaque.keep, "failed owner Retry restarted consumer");
          var base = Service.getPluginAPI("hello-world");
          root.check(base !== null, "restarted instance base registered");
          var instance = PluginInstances.apiFor("hello-world", root.placement);
          root.check(instance.pluginSettings.message === "catalog-instance", "restarted actual instance consumer");
          root.check(Settings.data.bar.widgets.left[0].opaque === "placement", "restarted unknown placement field");
          if (cases.some(function (item) {
            return item.manifest.id === "catwalk";
          })) {
            var cat = Service.getPluginAPI("catwalk");
            root.createMain(cat);
            var selected = PluginInstances.apiFor("catwalk", root.mainPlacement);
            root.check(cat.mainInstance.minimumThreshold === 10 && cat.mainInstance.hideBackground, "restarted shared Main consumer");
            root.check(selected.pluginSettings.minimumThreshold === 18 && selected.pluginSettings.hideBackground === false, "restarted selected instance consumer");
            root.check(Settings.data.bar.widgets.left[1].opaque === "main-placement", "restarted selected row unknown data");
          }
          console.log("I4_CATALOG: RESTART_PASS");
          Qt.exit(0);
        } catch (error) {
          console.error(String(error));
          Qt.exit(2);
        }
      });
      return;
    }
    var item = cases[index];
    Service.loadPluginSettings(item.manifest.id, function (value) {
      try {
        var restarted = Service.createPluginAPI(item.manifest.id, item.manifest, value, {}, {}, {});
        root.check(restarted.pluginSettings[item.key] === item.finalValue, "restarted actual API consumer " + item.manifest.id);
        root.check(restarted.pluginSettings.opaque.keep, "restarted unknown preference " + item.manifest.id);
        var plugins = Object.assign({}, Service.loadedPlugins);
        plugins[item.manifest.id] = {
          api: restarted
        };
        Service.loadedPlugins = plugins;
        root.index++;
        root.verifyNext();
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    });
  }

  function start() {
    if (started || !Settings.isLoaded)
      return;
    inputs.waitForJob();
    cases = JSON.parse(inputs.text());
    started = true;
    var version = Version.currentVersion;
    var known = Version.versionKnown;
    try {
      Version.versionKnown = true;
      Version.currentVersion = "0.9.1";
      for (var i = 0; i < cases.length; i++)
        check(Service.checkPluginCompatibility(cases[i].manifest).compatible === (cases[i].olderCompatible === true), "old-shell capability floor matches actual dependency");
      Version.currentVersion = "0.10.0";
      for (var j = 0; j < cases.length; j++)
        check(Service.checkPluginCompatibility(cases[j].manifest).compatible, "selected release admits page");
    } finally {
      Version.currentVersion = version;
      Version.versionKnown = known;
    }
    if (verifyOnly) {
      verifyNext();
      return;
    }
    if (mainOnly) {
      openMainInstance();
      return;
    }
    register(cases[index]);
    popup.openPluginSettings(manifest, "settings");
    phase = "pristine";
  }

  function drive() {
    if (verifyOnly || phase === "start")
      return;
    var p = page();
    var item = cases[index];
    if (phase === "pristine" && popup.opened && p) {
      check(typeof p.settingsDirty === "boolean", "actual page declares buffered dirtiness");
      check(!popup.dirty && applies === index * 2, "constructor does not stage preferences");
      for (var i = 0; i < item.buffers.length; i++) {
        var field = item.buffers[i];
        var before = p[field];
        p[field] = typeof before === "boolean" ? !before : typeof before === "number" ? before + 1 : before + "-dirty";
        check(p.settingsDirty && popup.dirty, "all local buffers tracked: " + field);
        p[field] = before;
        check(!p.settingsDirty, "local revert clean: " + field);
      }
      if (manifest.id === "git-companion") {
        var input = numericInput(p);
        check(input !== null, "actual Git Companion numeric input");
        input.forceActiveFocus();
        input.text = "";
        input.insert(0, "61");
        check(p.valueRefreshInterval === 60 && popup.dirty, "unblurred native numeric input is dirty");
      }
      p[item.field] = item.finalValue;
      popup.requestClose();
      check(popup.discardPending && api.pluginSettings[item.key] !== item.finalValue, "buffered Close confirms without Save");
      popup.keepEditing();
      check(popup.visible && p[item.field] === item.finalValue, "keep buffer");
      popup.requestClose();
      popup.confirmDiscard();
      phase = "reopen";
    } else if (phase === "reopen" && !popup.visible && !popup.currentPlugin) {
      check(applies === index * 2, "discard never applies");
      popup.openPluginSettings(manifest, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && p) {
      p[item.field] = item.finalValue;
      if (manifest.id === "launcher-pass") {
        p.editTypeDelay = "not-a-number";
        p.editWtypeDelay = "-2";
      } else if (manifest.id === "monitor-layout") {
        p.editGridSize = "-4";
      }
      if (manifest.id === "git-companion") {
        var input = numericInput(p);
        input.forceActiveFocus();
        input.text = "";
        input.insert(0, "61");
        check(p.valueRefreshInterval === 60 && popup.dirty, "Apply sees active numeric buffer before blur");
      }
      console.log("I4_CATALOG_PENDING", manifest.id);
      popup.applySettings();
      popup.applySettings();
      popup.requestClose();
      check(popup.busy && popup.visible && applies === index * 2 + 1, "one Apply and busy retention");
      phase = "held";
    } else if (phase === "held" && release) {
      check(popup.busy && held.status === "saved", "actual saved receipt held");
      deliver();
      check(!popup.busy && !popup.dirty && !popup.saveFailed && api.pluginSettings[item.key] === item.finalValue, "accepted current refresh");
      if (manifest.id === "git-companion")
        check(api.pluginSettings.refreshInterval === 61, "actual page gathered committed numeric input");
      if (manifest.id === "launcher-pass")
        check(p.editTypeDelay === "500" && p.editWtypeDelay === "12" && api.pluginSettings.typeDelay === 500 && api.pluginSettings.wtypeDelay === 12, "existing delay fallback reflected in displayed and saved values");
      if (manifest.id === "monitor-layout")
        check(p.editGridSize === "1" && api.pluginSettings.gridSize === 1, "existing grid clamp reflected in displayed and saved values");
      console.log("I4_CATALOG_PENDING", manifest.id);
      popup.applySettings();
      phase = "noop";
    } else if (phase === "noop" && release) {
      check(held.status === "nothing_to_save", "ordered real no-op");
      deliver();
      popup.requestClose();
      check(!popup.discardPending, "clean acknowledged close");
      phase = "next";
    } else if (phase === "next" && !popup.visible && !popup.currentPlugin) {
      index++;
      if (index < cases.length) {
        register(cases[index]);
        popup.openPluginSettings(manifest, "settings");
        phase = "pristine";
      } else {
        index = 0;
        register(cases[0]);
        makeStale = true;
        popup.openPluginSettings(manifest, "settings");
        phase = "stale";
      }
    } else if (phase === "stale" && popup.opened && p) {
      p.valueMessage = "saved-stale";
      console.log("I4_CATALOG_PENDING", manifest.id);
      popup.applySettings();
      phase = "stale-held";
    } else if (phase === "stale-held" && release) {
      check(held.status === "saved" && held.refreshState === "stale", "real saved-but-stale receipt");
      deliver();
      check(popup.saveFailed && popup.dirty && p.valueMessage === "saved-stale" && api.pluginSettings.message === "foreign-live", "stale feedback retains both values");
      popup.requestClose();
      popup.confirmDiscard();
      makeStale = false;
      phase = "final-open";
    } else if (phase === "final-open" && !popup.visible && !popup.currentPlugin) {
      popup.openPluginSettings(manifest, "settings");
      phase = "final";
    } else if (phase === "final" && popup.opened && p) {
      p.valueMessage = item.finalValue;
      console.log("I4_CATALOG_PENDING", manifest.id);
      popup.applySettings();
      phase = "final-held";
    } else if (phase === "final-held" && release) {
      deliver();
      check(!popup.saveFailed && !popup.dirty, "newer explicit Apply retained");
      popup.requestClose();
      phase = "failure-open";
    } else if (phase === "failure-open" && !popup.visible && !popup.currentPlugin) {
      var failure = JSON.parse(JSON.stringify(cases[0].manifest));
      failure.id = "i4-catalog-fail";
      register({
                 manifest: failure
               });
      popup.openPluginSettings(manifest, "settings");
      phase = "failure";
    } else if (phase === "failure" && popup.opened && p) {
      p.valueMessage = "failed-local";
      console.log("I4_CATALOG_PENDING", manifest.id);
      popup.applySettings();
      phase = "failure-held";
    } else if (phase === "failure-held" && release) {
      check(held.status === "failed", "real destination failure");
      deliver();
      check(popup.saveFailed && popup.dirty && p.valueMessage === "failed-local", "failed receipt retains catalog buffer");
      popup.requestClose();
      check(popup.discardPending, "failed Close requires explicit discard");
      popup.keepEditing();
      repair.running = true;
      phase = "repair";
    } else if (phase === "retry" && p) {
      p.valueMessage = "failure-newer";
      console.log("I4_CATALOG_PENDING", manifest.id);
      popup.applySettings();
      phase = "retry-held";
    } else if (phase === "retry-held" && release) {
      check(held.status === "saved" && held.refreshState === "current", "actual newer-input Retry receipt");
      deliver();
      check(!popup.saveFailed && !popup.dirty && api.pluginSettings.message === "failure-newer", "newer input saved after repaired destination");
      popup.requestClose();
      phase = "instance-open";
    } else if (phase === "instance-open" && !popup.visible && !popup.currentPlugin) {
      manifest = cases[0].manifest;
      api = Service.getPluginAPI("hello-world");
      Settings.data.bar.widgets.left = [
            {
              id: "plugin:hello-world",
              opaque: "placement",
              instanceSettings: {
                message: "instance"
              }
            }
          ];
      var instance = PluginInstances.apiFor("hello-world", placement);
      popup.openInstanceSettings(manifest, instance, "settings");
      phase = "instance";
    } else if (phase === "instance" && popup.opened && p) {
      check(p.valueMessage === "instance" && !popup.dirty, "actual catalog instance page");
      p.valueMessage = "catalog-instance";
      console.log("I4_CATALOG_PENDING", "instance:hello-world");
      popup.applySettings();
      phase = "instance-wait";
    } else if (phase === "instance-wait" && !popup.busy) {
      console.log("I4_CATALOG_INSTANCE_COMPLETE");
      check(!popup.saveFailed && PluginInstances.entryFor(placement).instanceSettings.message === "catalog-instance", "actual catalog instance persistence receipt");
      check(api.pluginSettings.message === cases[0].finalValue, "instance never replaces shared value");
      popup.requestClose();
      phase = cases.some(function (value) {
        return value.manifest.id === "catwalk";
      }) ? "main-open" : "finish";
    } else if (phase === "main-open" && !popup.visible && !popup.currentPlugin) {
      openMainInstance();
    } else if (phase === "main-instance" && popup.opened && p) {
      check(api.mainInstance.minimumThreshold === 10, "shared Main still has base threshold");
      check(p.valueMinimumThreshold === 17 && p.valueHideBackground === false, "selected instance inputs prefer page API to shared Main");
      if (mainOnly) {
        console.log("I4_MAIN_SCOPE: INPUT_PASS");
        Qt.exit(0);
        return;
      }
      p.valueMinimumThreshold = 18;
      console.log("I4_CATALOG_PENDING", "instance:catwalk");
      popup.applySettings();
      phase = "main-instance-wait";
    } else if (phase === "main-instance-wait" && !popup.busy) {
      check(!popup.saveFailed && PluginInstances.entryFor(mainPlacement).instanceSettings.minimumThreshold === 18, "selected threshold persistence receipt");
      check(api.mainInstance.minimumThreshold === 10 && api.mainInstance.hideBackground, "selected edit never changes shared Main");
      popup.requestClose();
      phase = "finish";
    } else if (phase === "finish" && !popup.visible && !popup.currentPlugin) {
      console.log("I4_CATALOG: SAVED_PASS");
      Qt.exit(0);
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.start();
    }
  }

  Process {
    id: repair
    command: ["python3", Quickshell.env("I4_CATALOG_REPAIR"), Quickshell.env("ATMOSPHERA_CONFIG_DIR")]
    onExited: function (code) {
      if (code !== 0) {
        console.error("I4_CATALOG_ASSERT: owned destination repair");
        Qt.exit(2);
      } else {
        root.phase = "retry";
      }
    }
  }

  FloatingWindow {
    visible: true
    implicitWidth: 860
    implicitHeight: 740
    NPluginSettingsPopup {
      id: popup
      parent: Overlay.overlay
      onSettingsCompleted: result => console.log("I4_CATALOG_POPUP_COMPLETE", result.status, result.refreshState)
    }
  }

  Component.onCompleted: start()
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Timer {
    interval: 100000
    running: true
    onTriggered: {
      console.error("I4_CATALOG_ASSERT: watchdog " + root.phase);
      Qt.exit(2);
    }
  }
}
