import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

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
  property var retainedWrite: null
  property var session: null
  property var externalPreview: null
  property var foreignEditor: null
  property var openedEditor: null
  property var hostWindow: null
  property var checkButton: null
  property bool a11yCompleted: false
  readonly property string scenario: Quickshell.env("PHA_OBSERVATION_SCENARIO")
  readonly property bool placed: Quickshell.env("PHA_OBSERVATION_SCOPE") === "instance"
  readonly property var selected: placed ? instance : api
  readonly property bool failInitialRead: ["failure", "newer-apply", "newer-check", "changed-draft"].includes(scenario)
  readonly property string expectedSavedValue: scenario === "newer-apply" && writes === 2 ? "newer-input" : "saved"
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
    property string buffer: ""
    readonly property bool settingsDirty: buffer !== ""
    function saveSettings() {
      writes++;
      if (buffer !== "")
        root.check(pluginApi.field("label").set(buffer), "buffered page input staged on Apply");
      pluginApi.saveSettings(function (result) {
        callbacks++;
        order += ",callback";
        last = result;
        // A generic page may treat a current saved result as an acknowledgment
        // of its buffer. Check again must not masquerade as that result.
        if (result?.status === "saved" && result.refreshState === "current")
          buffer = "";
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
          root.check(root.selected.settingsContext.settingsView.label === root.expectedSavedValue, "actual runtime consumer installed before signal");
          root.frozen = result.runtimeRead.snapshot;
          root.check(root.frozen.state(["label"]).value === root.expectedSavedValue, "immutable native selected snapshot");
        }
      }
    }
  }
  Component {
    id: windowFactory
    Window {
      width: 700
      height: 420
      visible: true
      title: "Observation fixture"
      property alias popup: popup
      property alias input: input
      TestEvent {
        id: input
      }
      NPluginSettingsPopup {
        id: popup
        parent: Overlay.overlay
        onSettingsCompleted: result => {
          root.signals++;
          root.last = result;
        }
      }
    }
  }
  function findItem(parent, name) {
    if (parent.objectName === name)
      return parent;
    for (var child of parent.children) {
      var item = findItem(child, name);
      if (item)
        return item;
    }
    return null;
  }
  Process {
    id: a11yPress
    command: ["/usr/bin/python3", "-B", Quickshell.env("PHA_OBSERVATION_A11Y_HELPER")]
    stderr: StdioCollector {
      id: a11yErrors
    }
    onExited: (code, status) => {
      if (code !== 0 || status !== 0)
        root.fail("external AT-SPI press failed: " + a11yErrors.text);
      else
        root.a11yCompleted = true;
    }
  }
  function drivePopup() {
    var popup = hostWindow.popup;
    if (phase === "popup-opening" && hostWindow.active && popup.opened && popup.settingsPage && I18n.isLoaded) {
      check(!findItem(popup.contentItem, "checkObservationButton"), "no Check again before failure");
      popup.settingsPage.setLabel("saved");
      check(popup.applySettings(), "popup applied actual page input");
      phase = "popup-held";
    } else if (phase === "popup-held" && held) {
      held(true);
      phase = "popup-failed";
    } else if (phase === "popup-failed" && !popup.busy) {
      check(signals === 1 && last.error.phase === "observation", "popup enters observation failure");
      popup.settingsPage.setLabel("newer-input");
      checkButton = findItem(popup.contentItem, "checkObservationButton");
      check(checkButton && checkButton.visible && checkButton.enabled && checkButton.activeFocusOnTab, "visible Check again enters tab chain");
      check(checkButton.Accessible.role === Accessible.Button && checkButton.Accessible.name === "Check again", "Check again accessible name and button role");
      check(hostWindow.input.keyClick(Qt.Key_Tab, Qt.NoModifier, 0), "Tab delivered");
      phase = "popup-focused";
    } else if (phase === "popup-focused") {
      check(checkButton.activeFocus, "Tab actually focuses Check again");
      phase = "popup-capturing";
      check(hostWindow.contentItem.grabToImage(function (image) {
        check(image.saveToFile(Quickshell.env("PHA_OBSERVATION_OUTPUT") + "/popup-check-focused.png"), "focused popup capture saved");
        phase = "popup-captured";
      }), "focused popup capture admitted");
    } else if (phase === "popup-captured") {
      check(hostWindow.input.keyClick(Qt.Key_Return, Qt.NoModifier, 0), "Return delivered to Check again");
      phase = "popup-retry-held";
    } else if (phase === "popup-retry-held" && held) {
      check(reads === 2 && popup.busy && !checkButton.enabled, "keyboard triggers only one check; busy action is disabled");
      held(true);
      phase = "popup-space";
    } else if (phase === "popup-space" && !popup.busy) {
      check(checkButton.activeFocus && popup.saveFailed && signals === 2, "failed check keeps its focused action");
      check(hostWindow.input.keyClick(Qt.Key_Space, Qt.NoModifier, 0), "Space delivered to Check again");
      phase = "popup-space-held";
    } else if (phase === "popup-space-held" && held) {
      check(reads === 3 && popup.busy, "Space triggers one check");
      held(true);
      phase = "popup-accessible";
    } else if (phase === "popup-accessible" && !popup.busy) {
      check(popup.saveFailed && signals === 3, "failed Space check retains the action");
      a11yPress.running = true;
      phase = "popup-accessible-held";
    } else if (phase === "popup-accessible-held" && held && a11yCompleted) {
      check(reads === 4 && popup.busy, "accessible press triggers one check");
      held(false);
      phase = "popup-checked";
    } else if (phase === "popup-checked" && !popup.busy) {
      check(!findItem(popup.contentItem, "checkObservationButton"), "successful Check again leaves no hidden tab stop or focus ring");
      check(signals === 4 && last.status === "observed" && last.write.status === "saved" && last.runtimeRead.snapshot.state(["label"]).value === "saved" && nativeReader.values.label === "saved", "keyboard and accessible actions checked the retained native write");
      check(popup.settingsPage.labelText === "newer-input" && popup.dirty, "newer popup input is still dirty");
      phase = "popup-capturing-checked";
      check(hostWindow.contentItem.grabToImage(function (image) {
        check(image.saveToFile(Quickshell.env("PHA_OBSERVATION_OUTPUT") + "/popup-check-complete.png"), "checked popup capture saved");
        finish();
      }), "checked popup capture admitted");
    }
  }
  function drive() {
    if (phase === "reader" && selected && selected.settingsReady && (scenario !== "inherited-preview" || !placed || instance._inheritedPreview?.ready)) {
      var wrapped = wrap(placed ? instance.runtime : api.settingsHandle);
      if (placed)
        instance.runtime = wrapped;
      else
        api.settingsOwner.settingsScope = wrapped;
      if (scenario === "popup-check") {
        hostWindow = windowFactory.createObject(root);
        check(hostWindow && (placed ? hostWindow.popup.openInstanceSettings(manifest, instance) : hostWindow.popup.openPluginSettings(manifest)), "open real selected popup");
        phase = "popup-opening";
        return;
      }
      session = sessionFactory.createObject(root);
      check(placed ? session.openInstanceSettings(manifest, instance) : session.openPluginSettings(manifest), "open selected session");
      phase = "opening";
    } else if (hostWindow) {
      drivePopup();
    } else if (phase === "apply") {
      openedEditor = session.editor;
      check(session.pageApi.field("label").set("saved"), "actual field intent");
      if (scenario === "preview-refused") {
        foreignEditor = selected.createSettingsEditor();
        check(foreignEditor, "foreign editor admitted");
        phase = "foreign-preview-opening";
        return;
      }
      if (scenario === "preview")
        check(session.pageApi.previewSettings({
                                                label: "saved"
                                              }), "explicit selected preview");
      check(session.applySettings(), "Apply admitted");
      phase = scenario === "inherited-preview" ? (placed ? "observed" : "foreign-preview-blocked") : "held";
    } else if (phase === "foreign-preview-opening" && foreignEditor.ready) {
      externalPreview = selected.createSettingsPreview(foreignEditor);
      check(externalPreview && externalPreview.update({
                                                        label: "foreign-preview"
                                                      }), "foreign owner holds selected preview");
      var field = session.pageApi.field("label");
      check(field.value === "saved" && field.pendingIntent === "set", "existing field intent before refused preview");
      check(!session.pageApi.previewSettings({
                                               label: "refused-patch"
                                             }), "foreign preview refuses page admission");
      check(field.value === "saved" && field.pendingIntent === "set", "refused preview preserves field intent");
      check(selected.settingsContext.settingsView.label === "foreign-preview", "foreign preview remains owned");
      check(externalPreview.close() && foreignEditor.discard(), "foreign owner releases its own editor");
      externalPreview = null;
      foreignEditor = null;
      check(session.applySettings(), "Apply original intent after refused preview");
      phase = "held";
    } else if (phase === "foreign-preview-blocked" && !session.busy) {
      check(last.status === "failed" && last.error.phase === "observation" && last.write.status === "saved", "foreign shared preview refuses observation, not the completed write");
      check(session.failed && writes === 1 && signals === 1 && callbacks === 1 && reads === 0, "foreign reader failure delivered once without a controlled native read");
      check(nativeReader.values.label === "saved" && selected.settingsContext.settingsView.label === "foreign-preview", "persisted native value and foreign preview remain distinct");
      check(externalPreview.close(), "foreign preview released by its owner");
      externalPreview = null;
      order = "";
      check(session.retryObservation(), "Check again after foreign preview release");
      phase = "foreign-preview-retry";
    } else if (phase === "foreign-preview-retry" && held) {
      check(session.busy && writes === 1 && reads === 1 && signals === 1 && callbacks === 1, "Retry waits for the selected native reader without restaging");
      var foreignRetry = held;
      foreignRetry(false);
      phase = "observed";
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
        releaseRead(failInitialRead);
        phase = failInitialRead ? "retry" : "observed";
      }
    } else if (phase === "retry" && !session.busy) {
      check(last.status === "failed" && last.error.phase === "observation" && last.write.status === "saved", "saved-but-unobserved failure is explicit");
      check(session.failed && signals === 1 && callbacks === 1 && writes === 1, "failed input retained and delivered once");
      retainedWrite = last.write;
      order = "";
      if (scenario === "newer-apply" || scenario === "newer-check")
        testPage.buffer = "newer-input";
      if (scenario === "newer-apply") {
        check(session.applySettings(), "Apply newer buffered page input");
        check(writes === 2, "Apply after observation failure stages newer buffered input");
      } else if (scenario === "changed-draft") {
        check(session.pageApi.field("label").set("new-native-draft") && session.editor.dirty, "native draft changed");
        check(session.retryObservation(), "Check again produces an explicit result");
        check(!session.busy && session.failed && session.dirty && !held && reads === 1 && writes === 1, "changed draft refuses before acquiring or saving");
        check(last.status === "failed" && last.error.phase === "observation" && last.error.code === "settings-observation-draft-changed" && last.write === retainedWrite, "changed draft refusal retains the original write");
        check(order === "signal,callback" && session.pageApi.field("label").value === "new-native-draft", "changed draft remains intact after the explicit refusal");
        finish();
        return;
      } else {
        check(session.retryObservation(), "Check again admitted");
      }
      phase = "retry-held";
    } else if (phase === "retry-held" && held) {
      check(writes === (scenario === "newer-apply" ? 2 : 1) && session.busy && reads === 2, "only Apply stages another write");
      check(!session.retryObservation(), "busy excludes another Check again");
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
                                                                    readerStateValid: !!root.frozen && root.frozen.state(["label"]).valid
                                                                  }));
      check(!session.failed && order === "signal,callback" && last.runtimeRead.status === "observed", "ordered complete observation");
      check(session.editor === openedEditor && session.page === testPage, "same editor/page survives observation");
      check(nativeReader.values.label === expectedSavedValue && frozen.state(["label"]).value === expectedSavedValue, "installed and immutable selected facts");
      if (scenario === "newer-apply")
        check(writes === 2 && signals === 2 && callbacks === 2 && last.status === "saved" && !testPage.settingsDirty && !session.dirty, "newer buffered Apply saved and acknowledged exactly once");
      else if (scenario === "newer-check")
        check(writes === 1 && signals === 2 && callbacks === 2 && last.status === "observed" && last.write === retainedWrite && testPage.buffer === "newer-input" && session.dirty, "Check again observed the retained write while newer input remains dirty");
      else if (scenario === "failure")
        check(writes === 1 && signals === 2 && callbacks === 2 && last.status === "saved" && last.observation === retainedWrite.observation && !session.dirty, "Check again delivered the unchanged page's retained write");
      check(!session.retryObservation(), "successful observation retires the retry action");
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
