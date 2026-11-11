// Actual informational settings page: construction/close must not create intent.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets
import "plugin-editor-probe.js" as EditorProbe

ShellRoot {
  id: root
  property bool started: false
  property int applies: 0
  property string phase: "start"
  property var api: null
  property var manifest: null
  FileView {
    id: inputs
    path: Quickshell.env("I4_READONLY_INPUTS")
    blockLoading: true
    printErrors: false
  }
  function check(value, label) {
    if (!value)
      throw new Error("I4_READONLY_ASSERT: " + label);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    inputs.waitForJob();
    manifest = JSON.parse(inputs.text());
    phase = "waiting-owner";
    if (typeof Service._openSettingsOwner === "function") {
      Service._openSettingsOwner(manifest.id, function (owner) {
        try {
          root.check(owner !== null, "actual native preference owner opened");
          root.register(owner);
        } catch (error) { console.error(String(error)); Qt.exit(2); }
      });
    } else register({});
  }
  function register(owner) {
    api = Service.createPluginAPI(manifest.id, manifest, owner, {}, {}, {});
    var factory = api.createSettingsEditor;
    api.createSettingsEditor = function () {
      var editor = factory();
      if (typeof api.settingsReady === "boolean") {
        root.check(editor && editor.ready && editor.writable === false && editor.fields.length === 0, "native informational session has no writable selection");
      }
      return EditorProbe.observe(editor, function () { root.applies++; });
    };
    var loaded = Object.assign({}, Service.loadedPlugins);
    loaded[manifest.id] = {
      api: api
    };
    Service.loadedPlugins = loaded;
    phase = "waiting-api";
  }
  function drive() {
    if (phase === "waiting-api") {
      check(!api.settingsOwner || api.settingsOwner.status !== "Error", "native owner open: " + (api.settingsOwner ? api.settingsOwner.error : ""));
      if (typeof api.settingsReady === "boolean" && !api.settingsReady) return;
      popup.openPluginSettings(manifest, "settings");
      phase = "opened";
    } else if (phase === "opened" && popup.opened && popup.settingsPage && popup.settingsPage.implicitHeight > 0) {
      check(typeof popup.settingsPage.saveSettings !== "function", "informational component has no writer");
      check(!popup.dirty && applies === 0, "constructor creates no intent");
      popup.applySettings();
      check(!popup.busy && !popup.dirty && applies === 0, "informational page cannot submit Apply");
      popup.requestClose();
      phase = "closed";
    } else if (phase === "closed" && !popup.visible && !popup.currentPlugin) {
      check(applies === 0, "Close never invokes Apply");
      console.log("I4_CATALOG_READONLY: PASS");
      phase = "finished";
      Qt.callLater(function () {
        Qt.exit(0);
      });
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 700
    implicitHeight: 500
    NPluginSettingsPopup {
      id: popup
      parent: Overlay.overlay
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error));
        Qt.callLater(function () {
          Qt.exit(2);
        });
      }
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("I4_READONLY_ASSERT: watchdog", root.phase);
      Qt.callLater(function () {
        Qt.exit(2);
      });
    }
  }
}
