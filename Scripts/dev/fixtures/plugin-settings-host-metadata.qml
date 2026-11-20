// Candidate compiler witness only. This does not claim P001 is corrected.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/todo/manifest.json"
    blockLoading: true
    printErrors: false
  }
  function check(condition, message) {
    if (!condition)
      throw new Error("METADATA_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    Qt.exit(2);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      todo: manifest
    };
    Service._openSettingsOwner("todo", function (owner) {
      try {
        check(owner !== null, "candidate native owner opened");
        var metadata = owner.store.settingsEditorMetadata;
        check(metadata.ready && metadata.error === "", "page metadata ready");
        check(Object.keys(metadata.fields).length === owner.store.settingsKeys.length, "complete declared-key coverage");
        for (var key of ["todos", "pages", "current_page_id"])
          check(metadata.fields[key].usage === "content", "protected content declared");
        for (var counter of ["count", "completedCount"])
          check(metadata.fields[counter].usage === "operational", "operational counters declared");
        check(metadata.fields.showCompleted.usage === "configuration", "config leaf declared");
        var api = Service.createPluginAPI("todo", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          todo: {
            api: api
          }
        };
        check(api.pluginSettings.todos.length === 2 && api.pluginSettings.current_page_id === 7, "existing content admission and runtime values unchanged");
        check(api.pluginSettings.settingsEditorMetadata === undefined, "metadata did not become a preference");
        var editor = api.createSettingsEditor();
        check(editor !== null, "native draft still opens");
        editor.whenReady(function (opened) {
          try {
            check(opened.status === "opened", "native draft ready");
            editor.apply(editor.values, function (result) {
              try {
                check(result.status === "nothing_to_save" && result.refreshState === "current", "untouched Apply remains nonpublishing");
                editor.discard();
                console.log("PLUGIN_SETTINGS_METADATA: NATIVE_READY (schema and content unchanged; no page writer yet)");
                Qt.exit(0);
              } catch (error) {
                fail(error);
              }
            });
          } catch (error) {
            fail(error);
          }
        });
      } catch (error) {
        fail(error);
      }
    });
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 45000
    running: true
    onTriggered: root.fail("native metadata watchdog")
  }
  Component.onCompleted: begin()
}
