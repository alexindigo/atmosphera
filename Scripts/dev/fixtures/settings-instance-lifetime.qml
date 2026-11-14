import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins
import "../../../Helpers/OwnedProcess.js" as OwnedProcess

ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_PLUGIN_DIR")
  property var api: null
  property var instance: null
  property var retained: null
  property bool started: false
  property bool submitted: false
  property int resetCompletions: 0
  property int unexpectedCompletions: 0
  property int checks: 0
  PluginPreferenceOwner {
    id: base
    pluginId: "i5-owner"
    pluginDirectory: root.directory + "/code"
    userFile: root.directory + "/user/settings.json"
    configFile: root.directory + "/user/config.json"
    cacheDirectory: root.directory + "/cache"
    evidenceDirectory: root.directory + "/evidence"
  }
  function check(ok, label) { if (!ok) throw new Error("I5_INSTANCE_LIFETIME_ASSERT: " + label); checks++; }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function protect(value, callback) {
    OwnedProcess.run(root, ["chmod", value, Settings.overridesDir], null, function (result) {
      try { check(result.success, "fault permission change"); callback(); }
      catch (error) { fail(error); }
    });
  }
  function openingCases() {
    var cancelled = PluginInstances.createSettingsEditor("i5-owner", instance.placement, api);
    cancelled.whenReady(function () { root.unexpectedCompletions++; });
    cancelled.destroy();
    var cancel = PluginInstances.openRuntime(api, instance.placement, function () { root.unexpectedCompletions++; });
    Qt.callLater(cancel);
    var missing = PluginInstances.createSettingsEditor("i5-owner", {kind: "bar", list: "global", section: "left", index: 999}, api);
    var synchronous = true;
    var opened = 0;
    missing.whenReady(function (result) {
      try {
        opened++;
        check(!synchronous && opened === 1 && result.status === "failed" && result.error.code === "overlay-selection", "one asynchronous open refusal");
        check(!missing.closed && missing.error === "overlay-selection", "refused editor observable until explicit discard");
        missing.discard();
        finish.start();
      } catch (error) { fail(error); }
    });
    synchronous = false;
  }
  function retry() {
    retained.resetOverrides(function (result) {
      try {
        check(result.status === "saved" && result.refreshState === "current", "same retained editor reset retry saves");
        check(PluginInstances.entryFor(instance.placement).instanceSettings === undefined, "retry removes only instance override");
        check(!retained.dirty && retained.ready && retained.discard(), "confirmed reset permits explicit discard");
        openingCases();
      } catch (error) { fail(error); }
    });
  }
  function begin() {
    if (!started && Settings.isLoaded && base.status === "Ready") {
      started = true;
      api = Service.createPluginAPI("i5-owner", {id: "i5-owner", metadata: {}}, base, {}, {}, {});
      Service.loadedPlugins["i5-owner"] = {api: api};
      instance = PluginInstances.apiFor("i5-owner", {kind: "bar", list: "global", section: "left", index: 0});
    }
    if (!instance || !instance.settingsReady || submitted) return;
    submitted = true;
    protect("0555", function () {
      retained = instance.resetSettings(function (result) {
        try {
          resetCompletions++;
          check(resetCompletions === 1 && result.status === "failed", "actual failed reset receipt");
          check(retained && !retained.closed && retained.ready && retained.handle && retained.dirty, "failed reset retains native editor and work");
          OwnedProcess.run(root, ["python3", "-c", "import json,sys; assert json.load(open(sys.argv[1]))['widgets']['left'][0]['instanceSettings']['label']=='custom'", Settings.filePathFor("bar")], null, function (readback) {
            try {
              check(readback.success, "failed reset preserves published file");
              protect("0755", retry);
            } catch (error) { fail(error); }
          });
        } catch (error) { fail(error); }
      });
    });
  }
  Timer { interval: 10; repeat: true; running: true; onTriggered: root.begin() }
  Timer {
    id: finish
    interval: 200
    onTriggered: {
      try {
        root.check(root.unexpectedCompletions === 0, "destroyed and cancelled open callbacks stay inert");
        Settings.store.close(function (result) {
          try {
            root.check(result.status === "nothing_to_save", "reset settled before close");
            base.store.close(function (shared) {
              try {
                root.check(shared.status === "nothing_to_save", "no shared save during instance reset");
                console.log("I5_INSTANCE_LIFETIME: PASS " + root.checks);
                Qt.exit(0);
              } catch (error) { root.fail(error); }
            });
          } catch (error) { root.fail(error); }
        });
      } catch (error) { root.fail(error); }
    }
  }
  Timer { interval: 30000; running: true; onTriggered: root.fail("lifetime timeout") }
}
