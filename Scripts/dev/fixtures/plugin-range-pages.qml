// Actual page constructors, native range consumers, held Apply and cold restart.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../Helpers/SettingsValues.js" as SettingsValues
import qs.Commons
import qs.Services.Plugins
import qs.Widgets
import "plugin-editor-probe.js" as EditorProbe

ShellRoot {
  id: root
  property var cases: []
  property int index: 0
  property var api: null
  property var held: null
  property var release: null
  property var completion: null
  property var submitted: null
  property bool newer: false
  property bool started: false
  property int applies: 0
  property string phase: "start"
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  FileView {
    id: inputs
    path: Quickshell.env("I4_RANGE_INPUTS")
    blockLoading: true
    printErrors: false
  }
  FileView { id: rawPreferences; blockLoading: true; printErrors: false }
  function rawUnknown() {
    rawPreferences.path = Quickshell.env("ATMOSPHERA_CONFIG_DIR") + "/settings/plugins/" + cases[index].id + ".json";
    rawPreferences.reload(); rawPreferences.waitForJob();
    check(JSON.parse(rawPreferences.text()).opaque.keep, "raw unknown preference retained");
  }
  function check(ok, label) {
    if (!ok) throw new Error("I4_RANGE_ASSERT: " + cases[index]?.id + ": " + label);
  }
  function control(item, field) {
    if (item.objectName === "settings-range-" + field) return item;
    for (var child of item.children || []) {
      var found = control(child, field);
      if (found) return found;
    }
    return null;
  }
  function domain(value, descriptor) {
    if (descriptor.inverse.startsWith(" / ")) return value / Number(descriptor.inverse.substring(3));
    if (descriptor.inverse.startsWith(" * ")) return value * Number(descriptor.inverse.substring(3));
    return value;
  }
  function snapshot(page) {
    var result = {};
    for (var descriptor of cases[index].controls) {
      var input = control(page, descriptor.field);
      check(input !== null, "actual range control " + descriptor.field);
      var displayed = domain(input.value, descriptor);
      check(Math.abs(page[descriptor.field] - displayed) < 0.0000001, "display equals gathered field " + descriptor.field);
      check(input.value >= Math.min(input.from, input.to) && input.value <= Math.max(input.from, input.to), "native range " + descriptor.field);
      result[descriptor.field] = input.value;
    }
    return result;
  }
  function move(page, descriptor, value) {
    var input = control(page, descriptor.field);
    input.value = value;
    if (descriptor.type === "NSpinBox") input.valueModified(input.value);
    else if (descriptor.type === "NValueSlider") input.moved(input.value);
    else input.moved();
  }
  function alternate(page, descriptor) {
    var input = control(page, descriptor.field);
    var low = Math.min(input.from, input.to);
    var high = Math.max(input.from, input.to);
    return input.value === low ? high : low;
  }
  function register(item, owner) {
    var component = Qt.createComponent("file://" + Registry.getPluginDir(item.id) + "/" + item.manifest.entryPoints.settings.split("?", 1)[0]);
    check(component.status === Component.Ready, "actual page component ready: " + component.errorString());
    api = Service.createPluginAPI(item.id, item.manifest, owner, {}, {}, {});
    var loaded = Object.assign({}, Service.loadedPlugins);
    loaded[item.id] = {api: api};
    Service.loadedPlugins = loaded;
    var original = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = original();
      return EditorProbe.observe(editor, function () { root.applies++; }, function (result, callback) {
        root.held = result;
        root.release = function () { callback(result); };
      });
    };
    popup.openPluginSettings(item.manifest, "settings");
    phase = "pristine";
  }
  function next() {
    if (index === cases.length) {
      console.log("I4_RANGE_PAGES: " + (verifyOnly ? "RESTART_PASS" : "SAVED_PASS"));
      Qt.exit(0);
      return;
    }
    var item = cases[index];
    applies = 0;
    newer = false;
    completion = null;
    phase = "waiting-owner";
    Service._openSettingsOwner(item.id, function (owner) {
        try {
          root.check(owner !== null, "actual native preference owner opened");
          root.rawUnknown();
          root.register(item, owner);
        } catch (error) { console.error(String(error)); Qt.exit(2); }
    });
  }
  function start() {
    if (started || !Settings.isLoaded) return;
    inputs.waitForJob();
    cases = JSON.parse(inputs.text());
    started = true;
    next();
  }
  function drive() {
    var page = popup.settingsPage;
    var item = cases[index];
    if (phase === "pristine" && popup.opened && page) {
      check(!popup.dirty && !page.settingsDirty && applies === 0, "constructor is clean without writer intent");
      var initial = snapshot(page);
      if (verifyOnly) {
        for (var key in item.expected) check(Math.abs(initial[key] - item.expected[key]) < 0.0000001, "cold displayed consumer " + key);
        popup.requestClose();
        phase = "closed";
        return;
      }
      for (var key in item.seed) {
        if (key !== "opaque") check(SettingsValues.equal(api.pluginSettings[key], item.seed[key]), "constructor preserves admitted " + key);
      }
      for (var descriptor of item.controls) move(page, descriptor, alternate(page, descriptor));
      snapshot(page);
      check(popup.dirty, "actual input is retained as local or staged work");
      for (var descriptor of item.controls) move(page, descriptor, initial[descriptor.field]);
      var reverted = snapshot(page);
      for (var key in initial) check(Math.abs(reverted[key] - initial[key]) < 0.0000001, "range edit/revert " + key);
      check(applies === 0, "native edits stage without applying");
      move(page, item.controls[0], alternate(page, item.controls[0]));
      submitted = snapshot(page);
      popup.applySettings();
      phase = "held";
    } else if (phase === "held" && release) {
      check(popup.busy && held.status !== "failed" && held.refreshState === "current", "actual range receipt held");
      if (item.plugin === "habitica" && item.mode === "low" && !newer) {
        check(api.pluginSettings.refreshInterval === submitted.editRefreshInterval, "first accepted numeric payload");
        move(page, item.controls[0], alternate(page, item.controls[0]));
        var local = snapshot(page);
        var callback = release; release = null; held = null; callback();
        check(popup.dirty && page.editRefreshInterval === local.editRefreshInterval, "newer native value survives older acknowledgement");
        newer = true;
        submitted = local;
        popup.applySettings();
        return;
      }
      var callback = release; release = null; held = null; callback();
      check(!popup.busy && !popup.saveFailed && !popup.dirty && !page.settingsDirty, "accepted range display is clean");
      var accepted = snapshot(page);
      console.log("I4_RANGE_EXPECTED|" + JSON.stringify({id: item.id, expected: accepted}));
      rawUnknown();
      popup.requestClose();
      check(!popup.discardPending, "acknowledged Close is clean");
      phase = "closed";
    } else if (phase === "closed" && !popup.visible && !popup.currentPlugin) {
      index++;
      phase = "next";
      next();
    }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.start(); } }
  FloatingWindow {
    visible: true
    implicitWidth: 860
    implicitHeight: 740
    NPluginSettingsPopup { id: popup; parent: Overlay.overlay }
  }
  Component.onCompleted: start()
  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      try { root.drive(); }
      catch (error) { console.error(String(error)); Qt.exit(2); }
    }
  }
  Timer { interval: 180000; running: true; onTriggered: { console.error("I4_RANGE_ASSERT: watchdog " + root.phase); Qt.exit(2); } }
}
