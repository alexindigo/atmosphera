import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property var api: null
  property var first: null
  property var second: null
  property var inherited: null
  property var failureApi: null
  property var selected: null
  property int familyIndex: 0
  readonly property var placements: [
    {kind: "bar", list: "global", section: "left", index: 0},
    {kind: "bar", list: "I4-preview-screen", section: "left", index: 0},
    {kind: "controlCenter", section: "left", index: 0},
    {kind: "desktop", screenName: "I4-preview-screen", index: 0}
  ]
  property var preview: null
  property var oldPreview: null
  property var captured: null
  property var release: null
  property var held: null
  property bool stale: false
  property string phase: "start"
  property bool started: false
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var manifest: ({id: "i4-preview", name: "Preview", entryPoints: {settings: "Preview.qml"}, metadata: {}})
  readonly property var placement: ({kind: "bar", list: "global", section: "left", index: 0})
  function check(ok, label) { if (!ok) throw new Error("I4_PREVIEW_ASSERT: " + phase + " " + label); }
  function register(value) {
    api = Service.createPluginAPI("i4-preview", manifest, value, {}, {}, {});
    var plugins = Object.assign({}, Service.loadedPlugins); plugins["i4-preview"] = {api: api}; Service.loadedPlugins = plugins;
    var factory = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = factory();
      var wrapper = {initialValue: editor.initialValue, discard: editor.discard, apply: function (value, callback) {
        editor.apply(value, function (result) {
          root.held = result;
          root.release = function () { if (result.refreshState === "current") wrapper.initialValue = editor.initialValue; callback(result); };
        });
        if (root.stale) root.api.pluginSettings = Object.assign({}, root.api.pluginSettings, {label: "foreign-current"});
      }};
      return wrapper;
    };
  }
  function start() {
    if (started || !Settings.isLoaded) return;
    started = true;
    if (verifyOnly) {
      Service.loadPluginSettings("i4-preview", function (value) {
        try { root.register(value); root.check(shared.text === "final" && root.api.pluginSettings.opaque.keep, "restarted consumer has only saved choices"); console.log("I4_PREVIEW: RESTART_PASS"); Qt.exit(0); }
        catch (error) { console.error(String(error)); Qt.exit(2); }
      });
      return;
    }
    register({label: "base", other: "old", opaque: {keep: true}});
    Settings.data.bar.widgets.left = [{id: "plugin:i4-preview", tag: "one", instanceSettings: {label: "one"}}, {id: "plugin:i4-preview", tag: "two", instanceSettings: {label: "two"}}, {id: "plugin:i4-preview", tag: "inherited"}];
    first = PluginInstances.apiFor("i4-preview", placement);
    second = PluginInstances.apiFor("i4-preview", {kind: "bar", list: "global", section: "left", index: 1});
    inherited = PluginInstances.apiFor("i4-preview", {kind: "bar", list: "global", section: "left", index: 2});
    preview = api.createSettingsPreview(); check(preview !== null && api.createSettingsPreview() === null, "one shared session");
    var patch = {label: "shared-preview"}; preview.update(patch); patch.label = "mutated-alias";
    phase = "shared";
  }
  function deliver() { var callback = release; release = null; held = null; callback(); }
  function familyRows() {
    if (familyIndex === 0) return Settings.data.bar.widgets.left;
    if (familyIndex === 1) return Settings.data.bar.screenOverrides[0].widgets.left;
    if (familyIndex === 2) return Settings.data.controlCenter.shortcuts.left;
    return Settings.data.desktopWidgets.monitorWidgets[0].widgets;
  }
  function replaceFamily(rows) {
    if (familyIndex === 0) Settings.data.bar.widgets.left = rows;
    else if (familyIndex === 2) Settings.data.controlCenter.shortcuts.left = rows;
    else if (familyIndex === 1) {
      var monitors = JSON.parse(JSON.stringify(Settings.data.bar.screenOverrides)); monitors[0].widgets.left = rows; Settings.data.bar.screenOverrides = monitors;
    } else {
      var monitors = JSON.parse(JSON.stringify(Settings.data.desktopWidgets.monitorWidgets)); monitors[0].widgets = rows; Settings.data.desktopWidgets.monitorWidgets = monitors;
    }
  }
  function nextFamily() {
    if (familyIndex === placements.length) { popup.openPluginSettings(manifest, "settings"); phase = "popup"; return; }
    selected = PluginInstances.apiFor("i4-preview", placements[familyIndex]); preview = selected.createSettingsPreview();
    check(preview !== null && preview.update({label: "selected-family"}), "placement preview opened"); phase = "family";
  }
  function drive() {
    if (verifyOnly || phase === "start") return;
    if (phase === "shared") {
      check(shared.text === "shared-preview" && inheritedText.text === "shared-preview" && firstText.text === "one" && secondText.text === "two", "bound runtime views and stored override precedence");
      check(api.pluginSettings.label === "base", "preview never edits preferences");
      api.pluginSettings = Object.assign({}, api.pluginSettings, {label: "foreign", other: "foreign-other"});
      phase = "foreign";
    } else if (phase === "foreign") {
      check(shared.text === "shared-preview" && other.text === "foreign-other", "foreign values visible outside preview patch");
      captured = preview.capture(); preview.update({label: "newer-preview", other: "newer-other"}); preview.acknowledge(captured);
      check(preview.pending(), "old revision cannot clear newer fields");
      phase = "revisions";
    } else if (phase === "revisions") {
      check(shared.text === "newer-preview" && other.text === "newer-other", "captured revision never acknowledges newer fields");
      oldPreview = preview; preview.close(); preview = api.createSettingsPreview(); preview.update({label: "replacement"}); oldPreview.close();
      phase = "replacement";
    } else if (phase === "replacement") {
      check(shared.text === "replacement", "obsolete close cannot clear replacement session"); preview.close();
      preview = first.createSettingsPreview(); preview.update({label: "instance-preview"}); phase = "instance";
    } else if (phase === "instance") {
      check(shared.text === "foreign" && firstText.text === "instance-preview" && secondText.text === "two", "selected placement isolation");
      var rows = Settings.data.bar.widgets.left.slice(); rows[0] = Object.assign({}, rows[0], {instanceSettings: {label: "foreign-instance"}}); Settings.data.bar.widgets.left = rows;
      phase = "instance-foreign";
    } else if (phase === "instance-foreign") {
      check(firstText.text === "instance-preview" && first.pluginSettings.label === "foreign-instance", "foreign instance preference keeps preview without rollback");
      preview.close(); check(firstText.text === "foreign-instance", "discard reveals current instance values");
      preview = first.createSettingsPreview(); preview.update({label: "captured-owner"});
      var rows = Settings.data.bar.widgets.left.slice(); Settings.data.bar.widgets.left = [rows[1], rows[0], rows[2]]; phase = "moved";
    } else if (phase === "moved") {
      check(firstText.text === "two" && !preview.update({label: "wrong-owner"}) && preview.pending(), "moved/replaced row cannot receive old preview; work retained");
      preview.close();
      var rows = [{id: "plugin:i4-preview", tag: "first", instanceSettings: {label: "first"}}, {id: "plugin:i4-preview", tag: "second", instanceSettings: {label: "second"}}];
      Settings.data.bar.widgets.left = rows;
      Settings.data.bar.screenOverrides = [{name: "I4-preview-screen", widgets: {left: rows, center: [], right: []}}];
      Settings.data.controlCenter.shortcuts.left = rows;
      Settings.data.desktopWidgets.monitorWidgets = [{name: "I4-preview-screen", widgets: rows}];
      nextFamily();
    } else if (phase === "family") {
      check(selectedText.text === "selected-family" && selected.pluginSettings.label === "first" && shared.text === "foreign", "placement consumer without shared mutation");
      var rows = familyRows().slice(); rows[0] = Object.assign({}, rows[0], {instanceSettings: {label: "foreign-family"}}); replaceFamily(rows); phase = "family-foreign";
    } else if (phase === "family-foreign") {
      check(selectedText.text === "selected-family" && selected.pluginSettings.label === "foreign-family", "same placement foreign preference retains preview");
      var rows = familyRows().slice(); replaceFamily([rows[1], rows[0]]); phase = "family-moved";
    } else if (phase === "family-moved") {
      check(selectedText.text === "second" && !preview.update({label: "wrong-placement"}) && preview.pending(), "all placement families fence replacement");
      preview.close(); familyIndex++; nextFamily();
    } else if (phase === "popup" && popup.opened && popup.settingsPage) {
      popup.settingsPage.change("submitted"); check(api.pluginSettings.label === "foreign" && popup.dirty, "popup previews without publishing");
      popup.applySettings(); phase = "held";
    } else if (phase === "held" && release) {
      check(held.status === "saved" && popup.busy, "actual held saved receipt");
      popup.settingsPage.change("newer-local"); deliver(); phase = "newer";
    } else if (phase === "newer") {
      check(api.pluginSettings.label === "submitted" && shared.text === "newer-local" && popup.dirty && popup.settingsPage.labelText === "newer-local", "acknowledgement preserves newer input and preview");
      popup.applySettings(); phase = "newer-held";
    } else if (phase === "newer-held" && release) {
      deliver(); check(!popup.dirty && shared.text === "newer-local", "current captured preview settles");
      popup.settingsPage.change("newer-local"); popup.applySettings(); phase = "noop-held";
    } else if (phase === "noop-held" && release) {
      check(held.status === "nothing_to_save", "actual no-op receipt"); deliver();
      check(!popup.dirty && shared.text === "newer-local", "no-op acknowledges its preview");
      stale = true; popup.settingsPage.change("saved-stale"); popup.applySettings(); phase = "stale-held";
    } else if (phase === "stale-held" && release) {
      check(held.status === "saved" && held.refreshState === "stale", "actual stale receipt"); deliver(); stale = false;
      check(popup.saveFailed && popup.dirty && shared.text === "saved-stale", "stale keeps preview and work");
      popup.requestClose(); popup.confirmDiscard(); phase = "discarded";
    } else if (phase === "discarded" && !popup.visible && !popup.currentPlugin) {
      check(shared.text === "foreign-current", "discard never restores opening snapshot");
      failureApi = Service.createPluginAPI("i4-preview-fail", manifest, {label: "failure-base"}, {}, {}, {});
      var plugins = Object.assign({}, Service.loadedPlugins); plugins["i4-preview-fail"] = {api: failureApi}; Service.loadedPlugins = plugins;
      popup.openPluginSettings({id: "i4-preview-fail", name: "Failure", entryPoints: {settings: "Preview.qml"}, metadata: {}}, "settings"); phase = "failure";
    } else if (phase === "failure" && popup.opened && popup.settingsPage) {
      popup.settingsPage.change("failed-local"); popup.applySettings(); phase = "failure-wait";
    } else if (phase === "failure-wait" && !popup.busy) {
      check(popup.saveFailed && popup.dirty && popup.settingsPage.labelText === "failed-local" && failedText.text === "failed-local", "actual IO failure retains input and preview");
      failureApi.pluginSettings = {label: "foreign-failed"}; popup.requestClose(); popup.confirmDiscard(); phase = "failure-discard";
    } else if (phase === "failure-discard" && !popup.visible && !popup.currentPlugin) {
      check(failedText.text === "foreign-failed", "failed discard reveals current preferences");
      popup.openPluginSettings(manifest, "settings"); phase = "final";
    } else if (phase === "final" && popup.opened && popup.settingsPage) {
      popup.settingsPage.change("final"); popup.applySettings(); phase = "final-held";
    } else if (phase === "final-held" && release) {
      deliver(); check(!popup.dirty && api.pluginSettings.label === "final", "final saved preferences"); popup.requestClose(); phase = "lifetime";
    } else if (phase === "lifetime" && !popup.visible && !popup.currentPlugin) {
      var temporary = Service.createPluginAPI("i4-dead-preview", manifest, {label: "alive"}, {}, {}, {});
      var plugins = Object.assign({}, Service.loadedPlugins); plugins["i4-dead-preview"] = {api: temporary}; Service.loadedPlugins = plugins;
      preview = temporary.createSettingsPreview(); temporary.destroy(); phase = "destroyed";
    } else if (phase === "destroyed") {
      check(!preview.update({label: "dead"}) && preview.close(), "callbacks after owner destruction are inert");
      console.log("I4_PREVIEW: SAVED_PASS"); Qt.exit(0);
    }
  }
  FloatingWindow {
    visible: true; implicitWidth: 760; implicitHeight: 600
    Column {
      Text { id: shared; text: root.api ? root.api.settingsView.label : "" }
      Text { id: other; text: root.api ? root.api.settingsView.other : "" }
      Text { id: firstText; text: root.first ? root.first.settingsView.label : "" }
      Text { id: secondText; text: root.second ? root.second.settingsView.label : "" }
      Text { id: inheritedText; text: root.inherited ? root.inherited.settingsView.label : "" }
      Text { id: failedText; text: root.failureApi ? root.failureApi.settingsView.label : "" }
      Text { id: selectedText; text: root.selected ? root.selected.settingsView.label : "" }
    }
    NPluginSettingsPopup { id: popup; parent: Overlay.overlay }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.start(); } }
  Component.onCompleted: start()
  Timer { interval: 50; repeat: true; running: true; onTriggered: { try { root.drive(); } catch (error) { console.error(String(error)); Qt.exit(2); } } }
  Timer { interval: 40000; running: true; onTriggered: { console.error("I4_PREVIEW_ASSERT: watchdog", root.phase); Qt.exit(2); } }
}
