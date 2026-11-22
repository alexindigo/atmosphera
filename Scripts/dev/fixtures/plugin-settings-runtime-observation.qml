import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  property var api: null
  property var instance: null
  property var nativeReader: null
  property var held: null
  property var manifest: null
  property string phase: "start"
  property int writes: 0
  property int signals: 0
  property int callbacks: 0
  property int reads: 0
  property string order: ""
  property var last: null
  property var frozen: null
  property var session: null
  property var externalPreview: null
  property var openedEditor: null
  readonly property string scenario: Quickshell.env("PHA_OBSERVATION_SCENARIO")
  readonly property bool placed: Quickshell.env("PHA_OBSERVATION_SCOPE") === "instance"
  readonly property var selected: placed ? instance : api
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/observation-fixture/manifest.json"
    blockLoading: true
    printErrors: false
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OBSERVATION_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function begin() {
    if (phase !== "start" || !Settings.isLoaded)
      return;
    phase = "owner";
    manifestFile.waitForJob();
    manifest = JSON.parse(manifestFile.text());
    Registry.installedPlugins = {
      "observation-fixture": manifest
    };
    Service._openSettingsOwner("observation-fixture", function (owner) {
      api = Service.createPluginAPI("observation-fixture", manifest, owner, {}, {}, {});
      Service.loadedPlugins = {
        "observation-fixture": {
          api: api
        }
      };
      if (scenario === "inherited-preview") {
        externalPreview = api.createSettingsPreview();
        check(externalPreview && externalPreview.update({
                                                          label: "foreign-preview"
                                                        }), "explicit shared preview");
      }
      if (placed)
        instance = PluginInstances.apiFor("observation-fixture", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
      phase = "reader";
    });
  }
  function wrap(reader) {
    nativeReader = reader;
    // Controlled collaborator wraps the exact real reader. It holds only the
    // acquisition request, never fabricates successful native observation.
    return {
      get ready() {
        return reader.ready;
      },
      get error() {
        return reader.error || "";
      },
      get values() {
        return reader.values;
      },
      get placementToken() {
        return reader.placementToken;
      },
      info: function (path) {
        return reader.info(path);
      },
      draft: function () {
        return reader.draft();
      },
      scope: function (path, writable) {
        return reader.scope(path, writable);
      },
      readProjection: {
        synchronize: function (after, callback) {
          reads++;
          check(!held, "one acquisition at a time");
          held = function (failed) {
            held = null;
            if (failed)
              callback({
                         status: "failed",
                         error: {
                           code: "controlled-read-failure"
                         }
                       });
            else
              reader.readProjection.synchronize(after, callback);
          };
          return "controlled-held-request";
        }
      }
    };
  }
  QtObject {
    id: testPage
    property var pluginApi: root.session ? root.session.pageApi : null
    readonly property bool settingsDirty: false
    function saveSettings() {
      writes++;
      pluginApi.saveSettings(function (result) {
        callbacks++;
        order += ",callback";
        last = result;
      });
    }
  }
  Component {
    id: sessionFactory
    PluginSettingsSession {
      page: testPage
      commitInputs: function () {}
      captureInputs: function () {
        return 0;
      }
      acknowledgeInputs: function (fence) {}
      resetInputs: function () {}
      onPresentRequested: root.phase = "apply"
      onOpeningFailed: root.fail("unexpected opening refusal")
      onSettingsCompleted: result => {
        root.signals++;
        root.order += "signal";
        root.last = result;
        if (result.refreshState === "current") {
          root.check(result.runtimeRead && result.runtimeRead.status === "observed", "native read receipt accompanies success");
          root.check(root.selected.settingsContext.settingsView.label === "saved", "actual runtime consumer installed before signal");
          root.frozen = result.runtimeRead.snapshot;
          root.check(root.frozen.state(["label"]).value === "saved", "immutable native selected snapshot");
        }
      }
    }
  }
  function drive() {
    if (phase === "reader" && selected && selected.settingsReady && (scenario !== "inherited-preview" || !placed || instance._inheritedPreview?.ready)) {
      session = sessionFactory.createObject(root);
      var wrapped = wrap(placed ? instance.runtime : api.settingsHandle);
      if (placed)
        instance.runtime = wrapped;
      else
        api.settingsOwner.settingsScope = wrapped;
      check(placed ? session.openInstanceSettings(manifest, instance) : session.openPluginSettings(manifest), "open selected session");
      phase = "opening";
    } else if (phase === "apply") {
      openedEditor = session.editor;
      check(session.pageApi.field("label").set("saved"), "actual field intent");
      if (scenario === "preview")
        check(session.pageApi.previewSettings({
                                                label: "saved"
                                              }), "explicit selected preview");
      check(session.applySettings(), "Apply admitted");
      phase = scenario === "inherited-preview" ? "observed" : "held";
    } else if (phase === "held" && held) {
      check(session.busy && session.pageApi.busy && signals === 0 && callbacks === 0, "busy and no observer before runtime acquisition");
      if (scenario === "preview")
        check(!session.pageApi.previewDirty && selected.settingsReadOwner === (placed ? instance.runtime : api.settingsHandle) && session.editor === openedEditor, "only acknowledged preview left; same editor and committed reader");
      check(!session.applySettings() && !session.requestClose() && !session.confirmDiscard(), "all competing actions excluded");
      if (scenario === "owner-loss") {
        Service.loadedPlugins = {};
        phase = "retired";
      } else if (scenario === "destroy") {
        session.destroy();
        var finishDestroyed = held;
        finishDestroyed(false);
        phase = "destroyed";
      } else {
        var releaseRead = held;
        releaseRead(scenario === "failure");
        phase = scenario === "failure" ? "retry" : "observed";
      }
    } else if (phase === "retry" && !session.busy) {
      check(last.status === "failed" && last.error.phase === "observation" && last.write.status === "saved", "saved-but-unobserved failure is explicit");
      check(session.failed && signals === 1 && callbacks === 1 && writes === 1, "failed input retained and delivered once");
      order = "";
      check(session.applySettings(), "observation-only Retry admitted");
      phase = "retry-held";
    } else if (phase === "retry-held" && held) {
      check(writes === 1 && session.busy && reads === 2, "Retry did not restage or write");
      var retry = held;
      retry(false);
      phase = "observed";
    } else if (phase === "observed" && !session.busy) {
      console.log("SETTINGS_OBSERVATION_RESULT " + JSON.stringify({
                                                                    status: last?.status,
                                                                    refreshState: last?.refreshState,
                                                                    error: last?.error,
                                                                    order: order,
                                                                    readerReady: selected.settingsReadOwner?.ready,
                                                                    readerStateValid: selected.settingsReadOwner?.readProjection.state(["label"]).valid
                                                                  }));
      check(!session.failed && order === "signal,callback" && last.runtimeRead.status === "observed", "ordered complete observation");
      check(session.editor === openedEditor && session.page === testPage, "same editor/page survives observation");
      check(nativeReader.values.label === "saved" && frozen.state(["label"]).value === "saved", "installed and immutable selected facts");
      if (scenario === "noop") {
        order = "";
        check(session.applySettings(), "no-op Apply admitted");
        phase = "noop-held";
      } else
        finish();
    } else if (phase === "noop-held" && held) {
      check(session.busy && last.status === "saved", "no-op also waits for reader");
      var noop = held;
      noop(false);
      phase = "noop-observed";
    } else if (phase === "noop-observed" && !session.busy) {
      check(["saved", "nothing_to_save"].indexOf(last.status) !== -1 && reads === 2 && order === "signal,callback", "equal/no-op receives its own observation");
      finish();
    } else if (phase === "retired" && !session.busy) {
      check(last.status === "failed" && last.error.code === "settings-runtime-owner" && signals === 1 && callbacks === 1, "owner loss fails without retargeting");
      var retired = held;
      retired(false);
      phase = "retired-late";
    } else if (phase === "retired-late") {
      check(signals === 1 && callbacks === 1, "late read cannot deliver twice");
      finish();
    } else if (phase === "destroyed") {
      check(signals === 0 && callbacks === 0, "destroyed session cannot receive a completion");
      finish();
    }
  }
  function finish() {
    console.log("SETTINGS_OBSERVATION: PASS " + (placed ? "instance" : "shared") + " " + scenario);
    Qt.exit(0);
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 30
    repeat: true
    running: true
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
