// Native shared-field preparation, independent of the generic page API.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property bool started: false
  property string phase: "opening"
  property var api: null
  property var editor: null
  property var fields: null
  property var threshold: null
  property var context: null
  property var receipt: null
  readonly property bool cold: Quickshell.env("PHA_SHARED_NATIVE_COLD") === "1"
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/catwalk/manifest.json"
    blockLoading: true
    printErrors: false
  }
  Text {
    id: runtimeText
    text: root.context ? String(root.context.settingsView.minimumThreshold) : ""
  }
  Text {
    id: fieldText
    text: root.threshold ? String(root.threshold.value) : ""
  }
  Component {
    id: fieldsFactory
    PluginSettingsFields {}
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("SHARED_NATIVE_ASSERT: " + phase + " " + message);
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
      catwalk: manifest
    };
    Service._openSettingsOwner("catwalk", function (owner) {
      try {
        check(!!owner, "native owner");
        api = Service.createPluginAPI("catwalk", manifest, owner, {}, {}, {});
        Service.loadedPlugins = {
          catwalk: {
            api: api
          }
        };
        context = api.settingsContext;
        check(context === api.settingsContext && context.current(), "stable current runtime context");
        phase = cold ? "cold" : "initial";
      } catch (error) {
        fail(error);
      }
    });
  }
  function open(next) {
    editor = api.createSettingsEditor(true);
    check(!!editor, "captured native draft");
    editor.whenReady(function (result) {
      try {
        check(result.status === "opened" && editor.fieldCapture.current(), "settled shared capture");
        fields = fieldsFactory.createObject(root, {
                                              editor: editor,
                                              scopeKind: "plugin",
                                              metadata: api.settingsOwner.store.settingsEditorMetadata,
                                              capture: editor.fieldCapture,
                                              recapture: function () {
                                                return Service.captureSharedSettingsFields(root.api);
                                              }
                                            });
        threshold = fields.field("minimumThreshold");
        check(threshold === fields.field("minimumThreshold"), "stable field handle");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function apply(next) {
    phase = "applying";
    editor.apply(editor.values, function (result) {
      try {
        receipt = result;
        check(result.status === "saved" && result.refreshState === "current", "native Apply current");
        check(fields.acknowledge(result), "receipt-bound recapture");
        phase = next;
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (phase === "initial" && runtimeText.text === "20") {
      open("reset-discard");
      phase = "opening-editor";
    } else if (phase === "reset-discard") {
      check(threshold.overridden && threshold.pendingIntent === "", "stored override facts");
      check(threshold.reset(), "stage native Reset");
      phase = "discard-staged";
    } else if (phase === "discard-staged" && threshold.pendingIntent === "reset" && fieldText.text === "10") {
      check(runtimeText.text === "20", "staging cannot publish");
      check(editor.discard(), "Discard native draft");
      fields.destroy();
      fields = null;
      threshold = null;
      phase = "opening-editor";
      open("set");
    } else if (phase === "set") {
      check(threshold.value === 20 && threshold.set(30), "Discard kept override and finite set admitted");
      apply("set-result");
    } else if (phase === "set-result" && runtimeText.text === "30") {
      check(context === api.settingsContext && threshold.overridden && !threshold.pendingIntent, "stable context and accepted stored facts");
      check(threshold.reset(), "second staged Reset");
      phase = "reset-staged";
    } else if (phase === "reset-staged" && threshold.pendingIntent === "reset" && fieldText.text === "10") {
      apply("reset-result");
    } else if (phase === "reset-result" && runtimeText.text === "10") {
      check(!threshold.overridden && !threshold.pendingIntent && context.current(), "native removal reveals lower level");
      check(editor.discard(), "release settled draft");
      console.log("PLUGIN_SETTINGS_SHARED_NATIVE: PASS");
      Qt.exit(0);
    } else if (phase === "cold" && runtimeText.text === "10") {
      check(api.pluginSettings.hideBackground && context.settingsView.hideBackground, "cold unrelated configuration consumer");
      console.log("PLUGIN_SETTINGS_SHARED_NATIVE: COLD_PASS");
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  Timer {
    interval: 20000
    running: true
    onTriggered: root.fail("watchdog " + root.phase)
  }
  Component.onCompleted: begin()
}
