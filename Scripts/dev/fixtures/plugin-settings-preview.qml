import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader {
    active: bootstrap.ready
    sourceComponent: Component {
  Item {
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
  property var afterFault: null
  property bool faultBlocked: false
  property bool exitAfterRepair: false
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  readonly property var manifest: ({id: "i4-preview", name: "Preview", entryPoints: {settings: "Preview.qml"}, metadata: {}})
  readonly property var placement: ({kind: "bar", list: "global", section: "left", index: 0})
  function check(ok, label) { if (!ok) throw new Error("I4_PREVIEW_ASSERT: " + phase + " " + label); }
  function fail(error){console.error(String(error));if(faultBlocked&&!faultProcess.running){exitAfterRepair=true;fault("repair",function(){});return;}Qt.exit(2);}
  function register(value) {
    api = Service.createPluginAPI("i4-preview", manifest, value, {}, {}, {});
    var plugins = Object.assign({}, Service.loadedPlugins); plugins["i4-preview"] = {api: api}; Service.loadedPlugins = plugins;
    var factory = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = factory();
      var wrapper = {initialValue: editor.initialValue, discard: editor.discard,
        get ready() { return editor.ready; }, get busy() { return editor.busy; }, get dirty() { return editor.dirty; },
        get closed() { return editor.closed; }, get error() { return editor.error; },
        get values() { return editor.values; }, get previewValues() { return editor.previewValues; },
        fields: editor.fields, whenReady: editor.whenReady, previewScope: editor.previewScope, copyValue: editor.copyValue,
        rebased: editor.rebased, destroy: function () { editor.destroy(); },
        apply: function (value, callback) {
        editor.apply(value, function (result) {
          root.held = result;
          root.release = function () { if (result.refreshState === "current") wrapper.initialValue = editor.initialValue; callback(result); };
        });
        if (root.stale) root.api.pluginSettings.label = "foreign-current";
      }};
      return wrapper;
    };
  }
  function start() {
    if (started || !Settings.isLoaded) return;
    started = true;
    Service._openSettingsOwner("i4-preview", function (owner) {
      try {
        check(owner !== null, "native preview preference owner opens");
        register(owner);
        if (verifyOnly) {
          check(shared.text === "final" && root.api.pluginSettings.opaque.keep, "restarted consumer has only saved choices");
          console.log("I4_PREVIEW: RESTART_PASS"); Qt.exit(0); return;
        }
    Settings.data.bar.widgets.left = [{id: "plugin:i4-preview", tag: "one", instanceSettings: {label: "one"}}, {id: "plugin:i4-preview", tag: "two", instanceSettings: {label: "two"}}, {id: "plugin:i4-preview", tag: "inherited"}];
    // Settle fixture setup before capturing any placement generation. An
    // autosave during open correctly invalidates a frozen displayed address.
    Settings.store.flush(function (result) {
      try {
        check(result.status === "saved" || result.status === "nothing_to_save", "initial placements saved");
    first = PluginInstances.apiFor("i4-preview", placement);
    second = PluginInstances.apiFor("i4-preview", {kind: "bar", list: "global", section: "left", index: 1});
    inherited = PluginInstances.apiFor("i4-preview", {kind: "bar", list: "global", section: "left", index: 2});
    preview = api.createSettingsPreview(); check(preview !== null && api.createSettingsPreview() === null, "one shared session");
    var patch = {label: "shared-preview"}; preview.update(patch); patch.label = "mutated-alias";
    phase = "shared";
      } catch (error) { console.error(String(error)); Qt.exit(2); }
    });
      } catch (error) { console.error(String(error)); Qt.exit(2); }
    });
  }
  // Native placement editors open asynchronously. This availability barrier is
  // before the original patch/foreign-edit/reorder schedule, not a new policy.
  function instancePreview(instance, callback) {
    var editor = instance.createSettingsEditor();
    check(editor !== null, "native placement preview capture");
    editor.whenReady(function (opened) {
      try {
        check(opened.status === "opened", "native placement preview opened: " + (opened.error?.code || opened.status));
        var session = instance.createSettingsPreview(editor);
        check(session !== null, "native placement preview session");
        var close = session.close;
        var closed = false;
        session.close = function () {
          if (closed) return true;
          if (!close()) return false;
          closed = true;
          return editor.discard();
        };
        callback(session);
      } catch (error) { console.error(String(error)); Qt.exit(2); }
    });
  }
  function openOther(id, callback) {
    Service._openSettingsOwner(id, function (owner) {
      try {
        check(owner !== null, "native auxiliary preference owner opens");
        var value = Service.createPluginAPI(id, manifest, owner, {}, {}, {});
        var plugins = Object.assign({}, Service.loadedPlugins); plugins[id] = {api: value}; Service.loadedPlugins = plugins;
        callback(value);
      } catch (error) { console.error(String(error)); Qt.exit(2); }
    });
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
    selected = PluginInstances.apiFor("i4-preview", placements[familyIndex]); phase = "opening-family";
    instancePreview(selected, function (session) {
      preview = session;
      check(preview !== null && preview.update({label: "selected-family"}), "placement preview opened"); phase = "family";
    });
  }
  function drive() {
    if (verifyOnly || phase === "start") return;
    if (phase === "shared") {
      if (![first, second, inherited].every(function (value) { return value.settingsReady && value._inheritedPreview && value._inheritedPreview.ready; })) return;
      check(shared.text === "shared-preview" && inheritedText.text === "shared-preview" && firstText.text === "one" && secondText.text === "two", "bound runtime views and stored override precedence");
      check(api.pluginSettings.label === "base", "preview never edits preferences");
      api.pluginSettings.label = "foreign"; api.pluginSettings.other = "foreign-other";
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
      phase = "opening-instance";
      instancePreview(first, function (session) { preview = session; preview.update({label: "instance-preview"}); phase = "instance"; });
    } else if (phase === "instance") {
      check(shared.text === "foreign" && firstText.text === "instance-preview" && secondText.text === "two", "selected placement isolation");
      var rows = Settings.data.bar.widgets.left.slice(); rows[0] = Object.assign({}, rows[0], {instanceSettings: {label: "foreign-instance"}}); Settings.data.bar.widgets.left = rows;
      phase = "instance-foreign";
    } else if (phase === "instance-foreign") {
      // The main owner and subscribed runtime handle publish on separate
      // workers. Wait for that actual consumer, not an arbitrary timer turn.
      if (first.pluginSettings.label !== "foreign-instance") return;
      check(firstText.text === "instance-preview" && first.pluginSettings.label === "foreign-instance", "foreign instance preference keeps preview without rollback");
      preview.close(); check(firstText.text === "foreign-instance", "discard reveals current instance values");
      phase = "opening-moved";
      instancePreview(first, function (session) {
        preview = session; preview.update({label: "captured-owner"});
        var rows = Settings.data.bar.widgets.left.slice(); Settings.data.bar.widgets.left = [rows[1], rows[0], rows[2]]; phase = "moved";
      });
    } else if (phase === "moved") {
      // The native token can invalidate preview before the live namespace has
      // delivered the replacement value. Observe that consumer, then assert.
      if (first.pluginSettings.label !== "two") return;
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
      if (selected.pluginSettings.label !== "foreign-family") return;
      check(selectedText.text === "selected-family" && selected.pluginSettings.label === "foreign-family", "same placement foreign preference retains preview");
      var rows = familyRows().slice(); replaceFamily([rows[1], rows[0]]); phase = "family-moved";
    } else if (phase === "family-moved") {
      if (selected.pluginSettings.label !== "second") return;
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
      popup.settingsPage.change("newer-local"); popup.applySettings(); phase = "equal-held";
    } else if (phase === "equal-held" && release) {
      check(held.status === "saved" && held.refreshState === "current", "explicit equal native input remains intent");deliver();
      popup.settingsPage.stageOnSave=false;popup.applySettings();phase="noop-held";
    } else if (phase === "noop-held" && release) {
      check(held.status === "nothing_to_save", "actual no-op receipt"); deliver();popup.settingsPage.stageOnSave=true;
      check(!popup.dirty && shared.text === "newer-local", "no-op acknowledges its preview");
      stale = true; popup.settingsPage.change("saved-stale"); popup.applySettings(); phase = "stale-held";
    } else if (phase === "stale-held" && release) {
      check(held.status === "saved" && held.refreshState === "stale", "actual stale receipt"); deliver(); stale = false;
      check(popup.saveFailed && popup.dirty && shared.text === "saved-stale", "stale keeps preview and work");
      popup.requestClose(); popup.confirmDiscard(); phase = "discarded";
    } else if (phase === "discarded" && !popup.visible && !popup.currentPlugin) {
      check(shared.text === "foreign-current", "discard never restores opening snapshot");
      phase = "opening-failure";
      openOther("i4-preview-fail-quarantine",function(quarantined){
        var refused=false;try{quarantined.pluginSettings.label="must-not-replace-directory";}catch(error){refused=String(error).indexOf("source-quarantined")!==-1;}
        check(refused,"startup directory source refuses input without replacing sentinel");
      openOther("i4-preview-fail", function (value) {
        failureApi = value;
        popup.openPluginSettings({id: "i4-preview-fail", name: "Failure", entryPoints: {settings: "Preview.qml"}, metadata: {}}, "settings"); phase = "failure";
      });
      });
    } else if (phase === "failure" && popup.opened && popup.settingsPage) {
      phase="failure-blocking";fault("block",function(){popup.settingsPage.change("failed-local");popup.applySettings();phase="failure-wait";});
    } else if (phase === "failure-wait" && !popup.busy) {
      check(popup.saveFailed && popup.dirty && popup.settingsPage.labelText === "failed-local" && failedText.text === "failed-local", "actual IO failure retains input and preview");
      phase="failure-repairing";fault("repair",function(){failureApi.pluginSettings.label="foreign-failed";popup.requestClose();popup.confirmDiscard();phase="failure-discard";});
    } else if (phase === "failure-discard" && !popup.visible && !popup.currentPlugin) {
      check(failedText.text === "foreign-failed", "failed discard reveals current preferences");
      popup.openPluginSettings(manifest, "settings"); phase = "final";
    } else if (phase === "final" && popup.opened && popup.settingsPage) {
      popup.settingsPage.change("final"); popup.applySettings(); phase = "final-held";
    } else if (phase === "final-held" && release) {
      deliver(); check(!popup.dirty && api.pluginSettings.label === "final", "final saved preferences"); popup.requestClose(); phase = "lifetime";
    } else if (phase === "lifetime" && !popup.visible && !popup.currentPlugin) {
      phase = "opening-destroyed";
      openOther("i4-dead-preview", function (temporary) { preview = temporary.createSettingsPreview(); temporary.destroy(); phase = "destroyed"; });
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
      Text { id: firstText; text: root.first && root.first.settingsView ? root.first.settingsView.label : "" }
      Text { id: secondText; text: root.second && root.second.settingsView ? root.second.settingsView.label : "" }
      Text { id: inheritedText; text: root.inherited && root.inherited.settingsView ? root.inherited.settingsView.label : "" }
      Text { id: failedText; text: root.failureApi ? root.failureApi.settingsView.label : "" }
      Text { id: selectedText; text: root.selected && root.selected.settingsView ? root.selected.settingsView.label : "" }
    }
    NPluginSettingsPopup { id: popup; parent: Overlay.overlay }
  }
  Connections { target: Settings; function onSettingsLoaded() { root.start(); } }
  Component.onCompleted: start()
  function fault(mode,callback){afterFault=callback;faultProcess.command=["python3","-B",Quickshell.env("I5_DESKTOP_FAULT"),Quickshell.env("ATMOSPHERA_CONFIG_DIR"),mode,"plugins"];faultProcess.running=true;}
  Process {id:faultProcess;onExited:code=>{try{root.check(code===0,"guarded real IO fault");root.faultBlocked=command[command.length-2]==="block";if(root.exitAfterRepair){Qt.exit(2);return;}var callback=root.afterFault;root.afterFault=null;callback();}catch(error){root.fail(error);}}}
  Timer { interval: 50; repeat: true; running: true; onTriggered: { try { root.drive(); } catch (error) { root.fail(error); } } }
  Timer { interval: 40000; running: true; onTriggered: { console.error("I4_PREVIEW_ASSERT: watchdog", root.phase); Qt.exit(2); } }
}
    }
  }
}
