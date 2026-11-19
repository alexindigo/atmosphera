import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

// Characterizes the native surfaces against the existing runtime instance API.
// A PASS here reports the refusals, not successful runtime API compatibility.
ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_PLUGIN_DIR")
  property bool started: false
  property var live: null
  PluginPreferenceOwner {
    id: base
    pluginId: "i5-owner"
    pluginDirectory: root.directory + "/code"
    userFile: root.directory + "/user/settings.json"
    configFile: root.directory + "/user/config.json"
    cacheDirectory: root.directory + "/cache"
    evidenceDirectory: root.directory + "/evidence"
    onSettled: {
      if (status === "Error") root.fail(error);
      else Qt.callLater(root.begin);
    }
  }
  Connections { target: Settings; function onSettingsLoaded() { Qt.callLater(root.begin); } }
  function fail(error) { console.error("I5_OVERLAY_RUNTIME_ASSERT: " + error); Qt.exit(2); }
  function options(mode) {
    return {mode: mode, base: base.settingsScope, ownerPath: ["bar", "widgets", "left"],
      ownerGeneration: Settings.store.info(["bar", "widgets", "left"]).publicationGeneration,
      entryPath: [{index: 0}], identityPath: [{key: "id"}], identityValue: "plugin:i5-owner",
      overrideKey: "instanceSettings", mergePolicy: "recursive_objects_replace_lists", differencePolicy: "top_level_omit_equal"};
  }
  function begin() {
    if (started || !Settings.isLoaded || base.status !== "Ready") return;
    started = true;
    Settings.store.setUser(["bar", "widgets", "left"], [{id: "plugin:i5-owner"}], function (written) {
      if (written.status !== "accepted") { fail("placement admission"); return; }
      Settings.store.openOverlay(options("view"), function (opened) {
        if (opened.status !== "opened") { fail("view " + opened.error?.code); return; }
        root.live = opened.editor;
        var rejected = false;
        try { root.live.values.label = "runtime-direct"; }
        catch (error) { rejected = true; console.log("I5_OVERLAY_RUNTIME_VIEW: " + error); }
        if (!rejected) { fail("expected readonly view refusal"); return; }
        Settings.store.openOverlay(options("editor"), function (result) {
          if (result.status !== "opened") { fail("editor " + result.error?.code); return; }
          var editor = result.editor;
          editor.values.label = "first-runtime";
          editor.apply(function (saved) {
            console.log("I5_OVERLAY_RUNTIME_RECEIPT: " + JSON.stringify(saved));
            if (saved.status !== "saved") { fail("editor save " + saved.error?.code); return; }
            editor.detach();
            root.live.detach();
            Settings.store.close(function (closed) {
              if (closed.status !== "nothing_to_save") { fail("owner close"); return; }
              base.store.close(function (baseClosed) {
                if (baseClosed.status !== "nothing_to_save") { fail("base close"); return; }
                console.log("I5_OVERLAY_RUNTIME: VIEW_READONLY=1 EDITOR_BUSY_REFUSAL=1");
                Qt.exit(0);
              });
            });
          });
          var busyRejected = false;
          try { editor.values.label = "second-runtime"; }
          catch (error) { busyRejected = true; console.log("I5_OVERLAY_RUNTIME_BUSY: " + error); }
          if (!busyRejected) fail("expected busy editor refusal");
        });
      });
    });
  }
  Component.onCompleted: Qt.callLater(begin)
  Timer { interval: 30000; running: true; onTriggered: root.fail("timeout") }
}
