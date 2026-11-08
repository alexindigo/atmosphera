// Inert actual-catalog pages on the old owner. Driver supplies owned local copies.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../Helpers/SettingsValues.js" as SettingsValues
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

  function checkValues(actual, expected, label) {
    for (var key in expected || {})
    check(SettingsValues.equal(actual[key], expected[key]), label + ": " + key);
  }

  function applyEdits(item, values) {
    for (var key in values || {})
    item[key] = values[key];
  }

  function timezoneToggle(item): var {
    if (typeof item.toggled === "function" && typeof item.checked === "boolean")
      return item;
    var nested = item.children || [];
    for (var i = 0; i < nested.length; i++) {
      var control = timezoneToggle(nested[i]);
      if (control)
        return control;
    }
    return null;
  }

  function toggles(item) {
    var result = [];
    if (typeof item.toggled === "function" && typeof item.checked === "boolean")
      result.push(item);
    for (var child of item.children || [])
      result = result.concat(toggles(child));
    return result;
  }

  function named(item, name) {
    if (item.objectName === name)
      return item;
    for (var child of item.children || []) {
      var found = named(child, name);
      if (found)
        return found;
    }
    return null;
  }

  function collectionWitness(p) {
    if (manifest.id === "battery-wireless-devices") {
      var devices = p.editDevices;
      var list = p.deviceList;
      p.set("fixture:one", "enabled", true);
      check(p.settingsDirty && p.editDevices["fixture:one"].enabled && p.editDevices["fixture:one"].opaque.keep, "device copy/replace notifies and retains unknown fields");
      p.editDevices = devices;
      check(!p.settingsDirty, "device field revert clean");
      p.moveDevice(0, 1);
      check(p.settingsDirty && p.deviceList[1].id === "fixture:one", "device reorder dirty");
      p.moveDevice(1, 0);
      check(!p.settingsDirty, "device reorder revert clean");
      p.removeDevice("fixture:one");
      check(p.settingsDirty && !p.editDevices["fixture:one"], "device removal stays local");
      p.editDevices = devices;
      p.deviceList = list;
      check(!p.settingsDirty && api.pluginSettings.devices["fixture:one"].opaque.keep, "device commands never publish or lose foreign data");
    } else if (manifest.id === "claude-code-panel") {
      var claude = p.editClaude;
      for (var key of ["binary", "workingDir", "model", "fallbackModel", "mcpConfigPath", "permissionMode", "autoResume", "includePartialMessages", "injectNoctaliaContext", "strictMcpConfig", "dangerouslySkipPermissions", "requireConfirmBypass"]) {
        p.set(key, typeof claude[key] === "boolean" ? !claude[key] : claude[key] + "-fixture");
        check(p.settingsDirty && !p._saveBlinking, "Claude record edit is local with no saved indicator: " + key);
        p.editClaude = claude;
        check(!p.settingsDirty, "Claude record revert clean: " + key);
      }
      p.pluginApi.settingsCompleted({
                                      status: "failed",
                                      refreshState: "not_refreshed"
                                    });
      p.pluginApi.settingsCompleted({
                                      status: "saved",
                                      refreshState: "stale"
                                    });
      check(!p._saveBlinking, "Claude failure/stale receipt never flashes saved");
    } else if (manifest.id === "hot-corners") {
      var corners = p.editCorners;
      for (var key of ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]) {
        p.updateCornerSetting(key, "fixture-command");
        check(p.settingsDirty && p.editCorners[key] === "fixture-command", "corner command copy/replace is dirty: " + key);
        p.editCorners = corners;
        check(!p.settingsDirty, "corner revert clean: " + key);
      }
      check(!api.pluginSettings.corners || !api.pluginSettings.corners.TopLeft, "corner command remains local");
    } else if (manifest.id === "model-usage") {
      var settings = p.editSettings;
      for (var provider of ["claude", "codex", "copilot", "gemini", "openrouter", "zen"]) {
        var enabled = settings.providers[provider].enabled;
        p.setProvider(provider, "enabled", !enabled);
        check(p.settingsDirty && p.editSettings.providers[provider].enabled !== enabled && api.pluginSettings.providers[provider].enabled === enabled, "provider local copy/replace: " + provider);
        p.editSettings = settings;
        check(!p.settingsDirty, "provider revert: " + provider);
      }
      for (var provider of ["openrouter", "zen"]) {
        p.setProvider(provider, "apiKey", "inert-fixture");
        check(p.settingsDirty && p.editSettings.providers[provider].apiKey === "inert-fixture", "provider key buffer tracked");
        p.editSettings = settings;
      }
    } else if (manifest.id === "caffeinate") {
      var presets = p.presetExpressions();
      check(presets.length === 2, "native preset source remains visible");
      p.setPreset(0, "15m");
      check(p.settingsDirty, "ListModel role edit is dirty at unchanged count");
      p.setPreset(0, presets[0]);
      check(!p.settingsDirty, "ListModel role revert is clean");
      p.movePreset(0, 1);
      check(p.settingsDirty, "ListModel move is dirty");
      p.movePreset(1, 0);
      check(!p.settingsDirty, "ListModel move revert is clean");
      p.addPreset("20m");
      check(p.settingsDirty, "ListModel append is dirty");
      p.removePreset(2);
      check(!p.settingsDirty, "ListModel remove/revert is clean");
      check(SettingsValues.equal(api.pluginSettings.presets, presets), "model commands never change the live owner");
      var alias = p.editAlias;
      var before = applies;
      p.editAlias = "!invalid";
      popup.applySettings();
      check(applies === before && popup.saveFailed && p.editAlias === "!invalid" && popup.dirty, "invalid alias refuses before writer and retains input");
      p.editAlias = alias;
      p.setPreset(0, "not-a-duration");
      popup.applySettings();
      check(applies === before && popup.saveFailed && p.presetExpressions()[0] === "not-a-duration", "invalid preset refuses before writer and retains model");
      p.replacePresets(presets);
    } else if (manifest.id === "custom-commands") {
      var rows = p.commands;
      check(rows.length === 2 && rows[0].opaque.keep, "actual command rows preserve unknown members");
      for (var key of ["name", "command", "icon"]) {
        p.setCommandField(0, key, rows[0][key] + "-edited");
        check(p.settingsDirty && p.commands[0].opaque.keep, "command field dirty and unknown retained: " + key);
        p.setCommandField(0, key, rows[0][key]);
        check(!p.settingsDirty, "command field revert: " + key);
      }
      p.moveCommand(0, 1);
      check(p.settingsDirty, "command reorder dirty");
      p.moveCommand(1, 0);
      check(!p.settingsDirty, "command reorder revert");
      p.addCommand();
      check(p.settingsDirty, "blank command input retained");
      p.setCommandField(2, "icon", "star");
      p.saveSettings();
      check(p.commands.length === 3 && p.commands[2].icon === "star" && p.settingsDirty, "staging retains an unadmitted blank command row");
      p.removeCommand(2);
      check(!p.settingsDirty, "command append/remove revert");
      check(SettingsValues.equal(api.pluginSettings.commands, rows), "command edits stay local");
    } else if (manifest.id === "special-workspaces") {
      var rows = p.workspaces;
      check(rows.length === 1 && rows[0].opaque.keep && rows[0].size === 0.3 && rows[0].borderRadius === 1, "nested row display projection and unknown data");
      for (var key of ["name", "icon", "symbolColor", "showPill", "pillColor", "focusColor"]) {
        p.setWorkspaceField(0, key, typeof rows[0][key] === "boolean" ? !rows[0][key] : rows[0][key] + "-edited");
        check(p.settingsDirty && p.workspaces[0].opaque.keep, "workspace field dirty: " + key);
        p.setWorkspaceField(0, key, rows[0][key]);
        check(!p.settingsDirty, "workspace field revert: " + key);
      }
      for (var pair of [["workspace-size-0", "size"], ["workspace-radius-0", "borderRadius"]]) {
        var slider = named(p, pair[0]);
        check(slider !== null, "actual nested row slider");
        check(slider.value === rows[0][pair[1]], "nested display equals gathered row");
        slider.value = rows[0][pair[1]] === slider.from ? slider.to : slider.from;
        slider.moved();
        check(p.settingsDirty && p.workspaces[0][pair[1]] === slider.value, "nested native edit updates local row");
        slider.value = rows[0][pair[1]];
        slider.moved();
        check(!p.settingsDirty, "nested native revert clean");
      }
      p.addWorkspace();
      check(p.settingsDirty, "workspace append is dirty");
      p.setWorkspaceField(1, "symbolColor", "secondary");
      p.saveSettings();
      check(p.workspaces.length === 2 && p.workspaces[1].symbolColor === "secondary" && p.settingsDirty, "staging retains an unadmitted unnamed workspace row");
      p.removeWorkspace(1);
      check(!p.settingsDirty, "workspace remove/revert clean");
      check(api.pluginSettings.workspaces[0].size === 0 && api.pluginSettings.workspaces[0].borderRadius === 100, "row display never rewrites admitted values during construction/edit");
    }
  }

  function register(item) {
    manifest = item.manifest;
    var component = Qt.createComponent("file://" + Registry.getPluginDir(manifest.id) + "/" + manifest.entryPoints.settings.split("?", 1)[0]);
    check(component.status === Component.Ready, "actual page component ready: " + component.errorString());
    api = Service.createPluginAPI(manifest.id, manifest, Object.assign({}, item.scenario?.seed || {}, {
                                                                         opaque: {
                                                                           keep: true
                                                                         }
                                                                       }), {}, {}, {});
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
        root.check(SettingsValues.equal(restarted.pluginSettings[item.key], item.finalValue), "restarted actual API consumer " + item.manifest.id);
        root.check(restarted.pluginSettings.opaque.keep, "restarted unknown preference " + item.manifest.id);
        root.checkValues(restarted.pluginSettings, item.scenario?.secondExpected || item.scenario?.expected, "restarted compound consumer " + item.manifest.id);
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
      checkValues(p, item.scenario?.initialDisplay, "existing constructor display policy");
      checkValues(api.pluginSettings, item.scenario?.seed, "constructor leaves admitted preferences unchanged");
      for (var i = 0; i < item.buffers.length; i++) {
        var field = item.buffers[i];
        var before = p[field];
        var restore = before;
        if (item.bufferTypes && item.bufferTypes[field] === "color")
          restore = before.valid ? Qt.rgba(before.r, before.g, before.b, before.a) : null;
        if (item.bufferTypes && item.bufferTypes[field] === "nullable-number")
          p[field] = before === null ? 18 : before + 1;
        else if (item.bufferTypes && item.bufferTypes[field] === "numeric-string")
          p[field] = String((Number(before) || 0) + 1);
        else if (item.bufferTypes && item.bufferTypes[field] === "color-string")
          p[field] = before === "#ff0000" ? "#00ff00" : "#ff0000";
        else if (item.bufferTypes && item.bufferTypes[field] === "color")
          p[field] = Qt.rgba(before.r < 0.5 ? 1 : 0, before.g, before.b, before.a);
        else if (Array.isArray(before))
          p[field] = before.concat(before.length ? [before[0]] : ["i4-dirty"]);
        else
          p[field] = typeof before === "boolean" ? !before : typeof before === "number" ? before + 1 : before + "-dirty";
        if (typeof before === "number" && p[field] === before)
          p[field] = before - 1;
        check(p.settingsDirty && popup.dirty, "all local buffers tracked: " + field);
        p[field] = restore;
        check(!p.settingsDirty, "local revert clean: " + field);
      }
      collectionWitness(p);
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
      check(popup.discardPending && !SettingsValues.equal(api.pluginSettings[item.key], item.finalValue), "buffered Close confirms without Save");
      popup.keepEditing();
      check(popup.visible && SettingsValues.equal(p[item.field], item.finalValue), "keep buffer");
      popup.requestClose();
      popup.confirmDiscard();
      phase = "reopen";
    } else if (phase === "reopen" && !popup.visible && !popup.currentPlugin) {
      check(applies === index * 2, "discard never applies");
      popup.openPluginSettings(manifest, "settings");
      phase = "apply";
    } else if (phase === "apply" && popup.opened && p) {
      p[item.field] = item.finalValue;
      applyEdits(p, item.scenario?.edits);
      if (manifest.id === "assistant-panel") {
        p.selectProvider("openai_compatible");
        p.selectProvider("google");
        var model = named(p, "assistant-model"), keyInput = named(p, "assistant-api-key");
        check(model !== null && keyInput !== null, "actual provider controls");
        model.inputItem.clear();
        model.inputItem.insert(0, "fixture-model");
        keyInput.inputItem.clear();
        keyInput.inputItem.insert(0, "fixture-token");
        check(p.editModels.openai_compatible === "retained-model" && p.editApiKeys.openai_compatible === "retained-token", "provider switch preserves the other provider's buffers");
        check(p.editModel === "fixture-model" && p.editApiKey === "fixture-token", "native current-provider fields gathered without child lookup");
      }
      if (manifest.id === "saved-desktop-widgets") {
        p.loadWidgets = true;
        var controls = toggles(p);
        check(controls.length === 2, "actual independent Save and Load toggles");
        controls[1].toggled(false);
        check(p.loadWidgets === false && p.saveWidgets === true && p.settingsDirty, "Load input never edits Save");
      }
      if (manifest.id === "rss-feed") {
        p.removeFeed(1);
        p.newFeedName = "  Added feed  ";
        p.newFeedUrl = "  https://example.test/feed  ";
        p.addFeed();
        check(p.feeds.length === 2 && api.pluginSettings.feeds[1].opaque.keep, "local collection commands preserve live/unknown rows until Apply");
      }
      if (manifest.id === "world-clock") {
        var toggle = timezoneToggle(p);
        check(toggle !== null, "actual timezone toggle exists");
        toggle.toggled(false);
        check(api.pluginSettings.timezones[0].enabled && api.pluginSettings.timezones[0].opaque.keep, "local row edit leaves live record unchanged");
      }
      if (manifest.id === "network-indicator")
        p.updateSlot(0, "none");
      if (manifest.id === "launcher-pass") {
        p.editTypeDelay = "not-a-number";
        p.editWtypeDelay = "-2";
      } else if (manifest.id === "monitor-layout") {
        p.editGridSize = "-4";
      }
      if (manifest.id === "git-companion" || manifest.id === "nvibrant") {
        if (manifest.id === "nvibrant")
          p.editVibranceValue = 640;
        var input = numericInput(p);
        input.forceActiveFocus();
        input.text = "";
        input.insert(0, manifest.id === "nvibrant" ? "641" : "61");
        check((manifest.id === "nvibrant" ? p.editVibranceValue === 640 : p.valueRefreshInterval === 60) && popup.dirty, "Apply sees active numeric buffer before blur");
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
      check(!popup.busy && !popup.dirty && !popup.saveFailed && SettingsValues.equal(api.pluginSettings[item.key], (manifest.id === "nvibrant" ? 641 : item.finalValue)), "accepted current refresh");
      checkValues(api.pluginSettings, item.scenario?.expected, "accepted compound settings");
      checkValues(p, item.scenario?.display, "display matches submitted normalization");
      if (manifest.id === "git-companion")
        check(api.pluginSettings.refreshInterval === 61, "actual page gathered committed numeric input");
      if (manifest.id === "launcher-pass")
        check(p.editTypeDelay === "500" && p.editWtypeDelay === "12" && api.pluginSettings.typeDelay === 500 && api.pluginSettings.wtypeDelay === 12, "existing delay fallback reflected in displayed and saved values");
      if (manifest.id === "monitor-layout")
        check(p.editGridSize === "1" && api.pluginSettings.gridSize === 1, "existing grid clamp reflected in displayed and saved values");
      console.log("I4_CATALOG_PENDING", manifest.id);
      applyEdits(p, item.scenario?.secondEdits);
      popup.applySettings();
      phase = "noop";
    } else if (phase === "noop" && release) {
      check(held.status === (manifest.id === "mullvad" ? "saved" : "nothing_to_save"), "ordered real second receipt");
      deliver();
      checkValues(api.pluginSettings, item.scenario?.secondExpected || item.scenario?.expected, "second receipt compound consumer");
      if (item.scenario?.retained) {
        check(popup.dirty, "unadmitted local input stays dirty after current no-op");
        checkValues(p, item.scenario.retained, "invalid input retained");
        popup.requestClose();
        check(popup.discardPending, "invalid input Close requires confirmation");
        popup.keepEditing();
        checkValues(p, item.scenario.retained, "Keep Editing retains invalid input");
        applyEdits(p, item.scenario.correction);
        check(!popup.dirty, "explicit correction returns to admitted value");
      }
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
