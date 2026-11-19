import QtQuick
import Quickshell
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_PLUGIN_DIR")
  readonly property bool restart: Quickshell.env("I5_PLUGIN_RESTART") === "1"
  property int checks: 0
  property bool started: false
  PluginPreferenceOwner {
    id: owner
    pluginId: "i5-owner"
    pluginDirectory: root.directory + "/code"
    userFile: root.directory + "/user/settings.json"
    configFile: root.directory + "/user/config.json"
    cacheDirectory: root.directory + "/cache"
    evidenceDirectory: root.directory + "/evidence"
    onSettled: {
      if (status === "Error") root.fail(error);
      else if (status === "Ready") Qt.callLater(root.begin);
    }
  }
  PluginPreferenceEditor { id: editor; fields: owner.store ? owner.store.settingsKeys : [] }
  PluginSettingsPreview {
    id: preview
    sourceValue: owner.settingsScope ? owner.settingsScope.values : null
    currentOwner: function () { return owner.settingsScope; }
    draftFactory: function () { return editor; }
  }
  readonly property string previewLabel: preview.values ? preview.values.label : ""
  function check(ok, label) { if (!ok) throw new Error("I5_PLUGIN_OWNER_ASSERT: " + label); checks++; }
  function fail(error) { console.error(String(error)); Qt.exit(2); }
  function finish() {
    owner.store.close(function (result) {
      try {
        check(result.status === "nothing_to_save", "settled close");
        console.log("I5_PLUGIN_OWNER: PASS " + (restart ? "cold " : "save ") + checks);
        Qt.exit(0);
      } catch (error) { fail(error); }
    });
  }
  function begin() {
    if (started) return;
    started = true;
    try {
      check(owner.settingsScope.values.label === (restart ? "saved" : "legacy"), "fallback/cold consumer");
      check(owner.settingsScope.values.amount === (restart ? 3 : 7), "whole-source fallback/default after user write");
      owner.snapshotConfig(function (config) {
        try {
          check(config.nested.a === 10 && config.nested.b === 2, "deep config worker merge");
          check(config.rows.length === 1 && config.rows[0] === "user", "config array replacement");
          config.nested.a = 99;
          check(owner.configScope.values.nested.a === 10, "owned explicit config read");
          if (restart) { finish(); return; }
          editor.attach(owner.settingsScope.draft());
          var session = preview.open(editor);
          check(session !== null && session.update({label: "first-preview"}), "native preview opens");
          var captured = session.capture();
          check(session.update({label: "saved"}) && session.acknowledge(captured) && session.pending(), "old acknowledgement retains newer input");
          check(root.previewLabel === "saved", "actual native draft preview consumer");
          check(owner.settingsScope.values.label === "legacy", "draft isolated from preferences");
          editor.apply(editor.values, function (result) {
            try {
              check(result.status === "saved" && result.refreshState === "current", "draft actual receipt");
              check(owner.settingsScope.values.label === "saved" && editor.initialValue.label === "saved", "confirmed consumers");
              check(owner.settingsScope.values.amount === 3, "user source shadows whole legacy");
              check(session.acknowledge(session.capture()) && !session.pending() && session.close(), "current preview acknowledgement and detach");
              check(editor.discard(), "editor detach without save");
              finish();
            } catch (error) { fail(error); }
          });
        } catch (error) { fail(error); }
      });
    } catch (error) { fail(error); }
  }
  Timer { interval: 30000; running: true; onTriggered: root.fail("plugin owner timeout") }
}
