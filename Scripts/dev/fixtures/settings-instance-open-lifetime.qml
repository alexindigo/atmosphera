import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string directory: Quickshell.env("I5_PLUGIN_DIR")
  readonly property string mode: Quickshell.env("I5_OPEN_CASE")
  readonly property var placement: ({
                                      kind: "bar",
                                      list: "global",
                                      section: "left",
                                      index: 0
                                    })
  property var api: null
  property var instance: null
  property var editor: null
  property bool started: false
  property bool testing: false
  property int retainedBefore: 0

  PluginPreferenceOwner {
    id: base
    pluginId: "i5-owner"
    pluginDirectory: root.directory + "/code"
    userFile: root.directory + "/user/settings.json"
    configFile: root.directory + "/user/config.json"
    cacheDirectory: root.directory + "/cache"
    evidenceDirectory: root.directory + "/evidence"
  }
  function check(ok, label) {
    if (!ok)
      throw new Error("I5_INSTANCE_OPEN_ASSERT: " + label);
  }
  function guard(callback) {
    try {
      callback();
    } catch (error) {
      console.error(String(error));
      Qt.exit(2);
    }
  }
  function finish() {
    guard(function () {
      check((Service._pluginEntries["i5-owner"] || []).length === retainedBefore, "no abandoned editor consumer");
      Settings.saveResult(function (result) {
        root.guard(function () {
          check(result.status !== "failed", "final owner save");
          Settings.store.close(function (closed) {
            root.guard(function () {
              check(closed.status !== "failed", "main owner closed");
              base.store.close(function (shared) {
                root.guard(function () {
                  check(shared.status !== "failed", "shared owner closed");
                  console.log("I5_INSTANCE_OPEN: PASS " + mode);
                  Qt.exit(0);
                });
              });
            });
          });
        });
      });
    });
  }
  function run() {
    retainedBefore = (Service._pluginEntries["i5-owner"] || []).length;
    if (mode === "preopen-swap") {
      editor = PluginInstances.createSettingsEditor("i5-owner", placement, api);
      var rows = Settings.store.copyValue(Settings.data.bar.widgets.left);
      Settings.data.bar.widgets.left = [rows[1], rows[0]];
      editor.whenReady(function (opened) {
        root.guard(function () {
          check(opened.status === "failed" && opened.error.code === "overlay-identity", "pre-open duplicate row replacement refused");
          check(Settings.data.bar.widgets.left[0].instanceSettings.label === "second", "replacement row unchanged");
          editor.discard();
          settle.start();
        });
      });
    } else if (mode === "preview-refusal") {
      check(instance.createSettingsPreview() === null, "unready factory preview refused synchronously");
      editor = instance.createSettingsEditor();
      check(instance.createSettingsPreview(editor) === null, "unready supplied preview refused synchronously");
      check(!editor.closed, "caller-supplied editor remains owned by caller");
      editor.discard();
      settle.start();
    } else if (mode === "reset-refusal") {
      editor = instance.resetSettings(function (opened) {
        root.guard(function () {
          check(opened.status === "failed", "one-shot reset opening refused");
          check(editor.closed, "failed one-shot opening discards its editor");
          settle.start();
        });
      });
      Settings.data.bar.widgets.left = [];
    } else {
      throw new Error("unknown opening case");
    }
  }
  function begin() {
    if (!started && Settings.isLoaded && base.status === "Ready") {
      started = true;
      api = Service.createPluginAPI("i5-owner", {
                                      id: "i5-owner",
                                      metadata: {}
                                    }, base, {}, {}, {});
      Service.loadedPlugins["i5-owner"] = {
        api: api
      };
      Settings.data.bar.widgets.left = [
            {
              id: "plugin:i5-owner",
              instanceSettings: {
                label: "first"
              }
            },
            {
              id: "plugin:i5-owner",
              instanceSettings: {
                label: "second"
              }
            }
          ];
      Settings.saveResult(function (result) {
        root.guard(function () {
          check(result.status !== "failed", "baseline saved");
          instance = PluginInstances.apiFor("i5-owner", placement);
        });
      });
    }
    if (testing || !instance || !instance.settingsReady)
      return;
    testing = true;
    guard(run);
  }
  Timer {
    interval: 10
    running: true
    repeat: true
    onTriggered: root.begin()
  }
  Timer {
    id: settle
    interval: 200
    onTriggered: root.finish()
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("I5_INSTANCE_OPEN_ASSERT: watchdog");
      Qt.exit(2);
    }
  }
}
