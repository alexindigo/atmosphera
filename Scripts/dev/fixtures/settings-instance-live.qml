import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_PLUGIN_DIR")
  readonly property bool restart: Quickshell.env("I5_INSTANCE_RESTART") === "1"
  readonly property bool previewOnly: Quickshell.env("I5_INSTANCE_PREVIEW") === "1"
  property var api: null
  property var instance: null
  property bool started: false
  property bool submitted: false
  property int completions: 0
  property int checks: 0
  property string previewStage: ""
  property var previewSession: null
  property var inheritedAmount: instance && instance.settingsReady && instance.settingsView ? instance.settingsView.amount : undefined
  PluginPreferenceOwner {
    id: base
    pluginId: "i5-owner"
    pluginDirectory: root.directory + "/code"
    userFile: root.directory + "/user/settings.json"
    configFile: root.directory + "/user/config.json"
    cacheDirectory: root.directory + "/cache"
    evidenceDirectory: root.directory + "/evidence"
    onSettled: { if (status === "Error") root.fail(error); }
  }
  function check(ok, label) { if (!ok) throw new Error("I5_INSTANCE_ASSERT: " + label); checks++; }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function close() {
    Settings.store.close(function (result) {
      try {
        check(result.status === "nothing_to_save", "main settled close");
        base.store.close(function (closed) {
          try {
            check(closed.status === "nothing_to_save", "shared file not saved by instance");
            console.log("I5_INSTANCE_LIVE: PASS " + (restart ? "cold " : "save ") + checks);
            Qt.exit(0);
          } catch (error) { fail(error); }
        });
      } catch (error) { fail(error); }
    });
  }
  function begin() {
    if (previewStage !== "") { drivePreview(); return; }
    if (!started && Settings.isLoaded && base.status === "Ready") {
      started = true;
      api = Service.createPluginAPI("i5-owner", {id: "i5-owner", metadata: {}}, base, {}, {}, {});
      Service.loadedPlugins["i5-owner"] = {api: api};
      instance = PluginInstances.apiFor("i5-owner", {kind: "bar", list: "global", section: "left", index: 0});
      check(instance !== null, "instance API created before entrypoint");
    }
    if (!instance || submitted) return;
    if (instance.settingsError) { fail(instance.settingsError); return; }
    if (!instance.settingsReady) return;
    submitted = true;
    try {
      check(instance.pluginSettings.amount === 7 && api.pluginSettings.label === "legacy", "real shared base consumer");
      if (previewOnly) {
        previewSession = api.createSettingsPreview();
        check(previewSession !== null && previewSession.update({amount: 9}), "shared native preview accepts input");
        check(api.settingsView.amount === 9 && api.pluginSettings.amount === 7, "shared preview isolated from preference");
        previewStage = "opening";
        return;
      }
      if (restart) {
        check(instance.pluginSettings.label === "live-second", "cold runtime instance consumer");
        close(); return;
      }
      instance.pluginSettings.label = "live-first";
      check(instance.pluginSettings.label === "live-first", "live immediate first input");
      instance.saveSettings(function (first) {
        try {
          console.log("I5_INSTANCE_RECEIPT: first " + JSON.stringify(first));
          check(first.status === "saved" && completions === 0, "first queued save receipt");
          check(instance.pluginSettings.label === "live-second", "older completion cannot roll back newer input");
          completions++;
        } catch (error) { fail(error); }
      });
      instance.pluginSettings.label = "live-second";
      instance.pluginSettings.amount = 7;
      check(instance.pluginSettings.label === "live-second" && !instance.runtime.busy, "writes accepted during save");
      instance.saveSettings(function (second) {
        try {
          console.log("I5_INSTANCE_RECEIPT: second " + JSON.stringify(second));
          check(second.status === "saved" && completions === 1, "second queued save receipt");
          check(instance.pluginSettings.label === "live-second" && api.pluginSettings.label === "legacy", "instance/base isolation after save");
          var row = PluginInstances.entryFor(instance.placement);
          check(row.instanceSettings.label === "live-second" && row.instanceSettings.amount === undefined, "native sparse difference consumer");
          check(Object.getOwnPropertyDescriptor(row, "__proto__").value.safe, "own opaque placement member");
          close();
        } catch (error) { fail(error); }
      });
    } catch (error) { fail(error); }
  }
  function drivePreview() {
    try {
      if(previewStage==="closed"){
        if(!instance.settingsReady||root.inheritedAmount!==api.pluginSettings.amount)return;
        check(api.pluginSettings.amount===3&&root.inheritedAmount===3,"closing preview reveals current whole-source inheritance, not opening legacy value");
        console.log("I5_INSTANCE_PREVIEW: PASS "+checks);Qt.exit(0);return;
      }
      if (previewStage === "opening") {
        if (!instance._inheritedPreview || !instance._inheritedPreview.ready) return;
        check(root.inheritedAmount === 9, "native instance consumer inherits shared preview");
        api.pluginSettings.label = "foreign-unrelated";
        previewStage = "foreign";
        return;
      }
      // The view is on another worker. Observe its final consumer rather than
      // treating one GUI callLater turn as a cross-worker completion fence.
      if (instance.settingsView.label !== "foreign-unrelated") return;
      var inherited = root.inheritedAmount;
      var unpreviewed = api.settingsView.label;
      console.log("I5_INSTANCE_PREVIEW_OBSERVED: " + JSON.stringify({
        sharedAmount: api.settingsView.amount, preferenceAmount: api.pluginSettings.amount,
        inheritedAmount: inherited, unpreviewedLabel: unpreviewed, preferenceLabel: api.pluginSettings.label
      }));
      check(inherited === 9 && unpreviewed === "foreign-unrelated", "shared inheritance and unpreviewed foreign fields follow current preview source");
      check(previewSession.close(), "shared preview closes");
      previewStage="closed";
    } catch (error) { fail(error); }
  }
  Timer { interval: 10; repeat: true; running: true; onTriggered: root.begin() }
  Timer { interval: 30000; running: true; onTriggered: root.fail("instance timeout") }
}
