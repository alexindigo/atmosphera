// Production session/loader/native owners, isolated presentation and consumers.
import QtQuick
import Quickshell
import Quickshell.Io
import "Helpers/SettingsListCommands.js" as Lists
import qs.Commons
import qs.Services.Plugins

ShellRoot {
  id: root
  readonly property string scenario: Quickshell.env("PHA_LIFETIME_SCENARIO")
  readonly property string family: Quickshell.env("PHA_LIFETIME_FAMILY")
  readonly property bool cold: Quickshell.env("PHA_LIFETIME_COLD") === "1"
  property bool started: false
  property string phase: "start"
  property var api: null
  property var selected: null
  property var sibling: null
  property bool reresolved: false
  property var session: null
  property var page: null
  property var nativeEditor: null
  property var held: null
  property var heldResult: null
  property bool retired: false
  property int acknowledgments: 0
  property int receipts: 0
  property var replacementEditor: null
  property var replacementPreview: null
  property var sharedSession: null
  property var sharedPage: null
  property double deadline: 0
  readonly property var placement: family === "shared" ? null : family === "global-bar" ? {
                                                                                            kind: "bar",
                                                                                            list: "global",
                                                                                            section: "left",
                                                                                            index: 0
                                                                                          } : family === "monitor-bar" ? {
    kind: "bar",
    list: "lifetime-screen",
    section: "left",
    index: 0
  } : family === "control-center" ? {
    kind: "controlCenter",
    section: "left",
    index: 0
  } : {
  kind: "desktop",
  screenName: "lifetime-screen",
  index: 0
}
property var manifest: null
FileView {
  id: manifestFile
  path: Settings.configDir + "plugins/lifetime-fixture/manifest.json"
  blockLoading: true
  printErrors: false
}
Component {
  id: heldFactory
  QtObject {
    id: wrapper
    required property var editor
    readonly property var fieldCapture: editor.fieldCapture
    readonly property var handle: editor.handle
    readonly property bool _releasePending: editor._releasePending
    readonly property var initialValue: editor.initialValue
    readonly property var values: editor.values
    readonly property var previewValues: editor.previewValues
    readonly property bool writable: editor.writable
    readonly property bool ready: editor.ready
    readonly property bool busy: editor.busy
    readonly property bool dirty: editor.dirty
    readonly property bool closed: editor.closed
    readonly property string error: editor.error
    readonly property var fields: editor.fields
    signal rebased(var result)
    property Connections rebaseConnection: Connections {
      target: wrapper.editor
      function onRebased(result) {
        wrapper.rebased(result);
      }
    }
    function whenReady(callback) {
      return editor.whenReady(callback);
    }
    function release() {
      return editor.release();
    }
    function discard() {
      return editor.discard();
    }
    function copyValue(value) {
      return editor.copyValue(value);
    }
    function setField(key, value) {
      return editor.setField(key, value);
    }
    function stageFieldResets(keys, callback) {
      return editor.stageFieldResets(keys, callback);
    }
    function unsetField(key) {
      return editor.unsetField(key);
    }
    function publishPreview(key, value, revision) {
      return editor.publishPreview(key, value, revision);
    }
    function previewScope() {
      return editor.previewScope();
    }
    function apply(value, callback) {
      editor.apply(value, function (receipt) {
        root.heldResult = receipt;
        root.held = function () {
          callback(receipt);
        };
      });
    }
  }
}
Component {
  id: sessionFactory
  PluginSettingsSession {
    id: selectedSession
    commitInputs: function () {}
    captureInputs: function () {
      return 1;
    }
    acknowledgeInputs: function () {
      root.acknowledgments++;
    }
    resetInputs: function () {}
    onPresentRequested: root.present(selectedSession)
    onSettingsCompleted: result => {
      root.receipts++;
      console.log("LIFETIME_RECEIPT", result.status, result.refreshState, result.error?.code || "");
    }
    onOpeningFailed: root.fail("selected session refused opening")
  }
}
Text {
  id: selectedText
  text: root.selected?.settingsView?.label ?? ""
}
Text {
  id: siblingText
  text: root.sibling?.settingsView?.label ?? ""
}
Text {
  id: sharedText
  text: root.api?.settingsView?.label ?? ""
}
Item {
  id: pageHost
}

function check(ok, message) {
  if (!ok)
    throw new Error("LIFETIME_ASSERT: " + scenario + "/" + family + "/" + phase + ": " + message);
}
function fail(error) {
  console.error(String(error) + "\n" + (error.stack || ""));
  Qt.exit(2);
}
function rows() {
  if (family === "global-bar")
    return Settings.data.bar.widgets.left;
  if (family === "monitor-bar")
    return Settings.data.bar.screenOverrides[0].widgets.left;
  if (family === "control-center")
    return Settings.data.controlCenter.shortcuts.left;
  return Settings.data.desktopWidgets.monitorWidgets[0].widgets;
}
function replaceRows(value) {
  if (family === "global-bar")
    Settings.data.bar.widgets.left = value;
  else if (family === "control-center")
    Settings.data.controlCenter.shortcuts.left = value;
  else if (family === "monitor-bar") {
    var bars = Settings.store.copyValue(Settings.data.bar.screenOverrides);
    bars[0].widgets.left = value;
    Settings.data.bar.screenOverrides = bars;
  } else {
    var desktops = Settings.store.copyValue(Settings.data.desktopWidgets.monitorWidgets);
    desktops[0].widgets = value;
    Settings.data.desktopWidgets.monitorWidgets = desktops;
  }
}
function ownerPath() {
  return family === "global-bar" ? ["bar", "widgets", "left"] : family === "monitor-bar" ? ["bar", "screenOverrides"] : family === "control-center" ? ["controlCenter", "shortcuts", "left"] : ["desktopWidgets", "monitorWidgets"];
}
function settled() {
  if (family === "shared")
    return true;
  return Lists.settled(Settings.store.info(ownerPath()));
}
function begin() {
  if (started || !Settings.isLoaded)
    return;
  started = true;
  manifestFile.waitForJob();
  manifest = JSON.parse(manifestFile.text());
  Registry.installedPlugins = {
    "lifetime-fixture": manifest
  };
  Service._openSettingsOwner("lifetime-fixture", function (owner) {
    try {
      check(owner !== null, "native plugin owner opened");
      api = Service.createPluginAPI("lifetime-fixture", manifest, owner, {}, {}, {});
      Service.loadedPlugins = {
        "lifetime-fixture": {
          api: api,
          manifest: manifest
        }
      };
      if (family === "shared")
        selected = api;
      else {
        selected = PluginInstances.apiFor("lifetime-fixture", placement);
        var other = Object.assign({}, placement, {
                                    index: 1
                                  });
        sibling = PluginInstances.apiFor("lifetime-fixture", other);
      }
      phase = "runtime";
      deadline = Date.now() + 15000;
    } catch (error) {
      fail(error);
    }
  });
}
function wrap(editor) {
  // Delay delivery, never manufacture or edit the native receipt.
  nativeEditor = editor;
  return heldFactory.createObject(root, {
                                    editor: editor
                                  });
}
function open() {
  var delayed = ["held", "destroy-delayed", "release-delayed"].indexOf(scenario) !== -1;
  var create = null;
  if (delayed && family === "shared") {
    create = selected.createSettingsEditor;
    selected.createSettingsEditor = function (fieldIntent) {
      return wrap(create(fieldIntent));
    };
  }
  session = sessionFactory.createObject(root);
  check(session !== null, "session constructed");
  check(family === "shared" || scenario === "preview-chain" ? session.openPluginSettings(manifest) : session.openInstanceSettings(manifest, selected, "settings", delayed ? wrap(selected.createSettingsEditor(true)) : null), "selected opening admitted");
  if (create)
    selected.createSettingsEditor = create;
  phase = "opening";
  deadline = Date.now() + 15000;
}
function present(value) {
  check(session === value, "selected presentation identity");
  var component = Qt.createComponent(session.settingsUrl);
  check(component.status === Component.Ready, "real page component: " + component.errorString());
  page = PluginLoader.createObject("lifetime-fixture", "settings", component, pageHost, session.pageApi, {});
  check(page !== null, "production loader created field-only page");
  session.page = page;
  session.presentationOpen = true;
  nativeEditor = nativeEditor || session.editor;
  check(page.labelText === "base" && acknowledgments === 0 && !session.dirty, "opening creates no intent");
  check(page.change(scenario === "preview-chain" && session.isInstance ? "instance-preview" : "local"), "explicit page preview accepted");
  if (scenario === "preview-chain") {
    if (session.isInstance)
      phase = "chain-instance";
    else {
      sharedSession = session;
      sharedPage = page;
      phase = "chain-shared";
    }
  } else
    phase = "preview";
  deadline = Date.now() + 15000;
}
function mutate() {
  phase = "mutation";
  deadline = Date.now() + 18000;
  if (scenario.indexOf("base-") === 0) {
    if (scenario === "base-aba")
      api.pluginSettings.label = "intermediate";
    api.pluginSettings.label = scenario === "base-change" ? "foreign" : "base";
    api.saveSettings(function (receipt) {
      try {
        check(receipt.status !== "failed", "foreign base publication acknowledged");
        phase = "mutated";
      } catch (error) {
        fail(error);
      }
    });
  } else if (scenario === "reorder" || scenario === "replace") {
    var current = Settings.store.copyValue(rows());
    replaceRows(scenario === "reorder" ? [current[1], current[0]] : [Object.assign({}, current[0], {
                                                                                     tag: "replacement",
                                                                                     instanceSettings: {
                                                                                       label: "replacement"
                                                                                     }
                                                                                   }), current[1]]);
    Settings.saveSelected([ownerPath()], function (receipt) {
      try {
        check(receipt.status !== "failed", "foreign placement publication");
        phase = "mutated";
      } catch (error) {
        fail(error);
      }
    });
  } else if (scenario === "source-replace" || scenario === "source-change") {
    sourceMutation.running = true;
  } else if (scenario === "unload") {
    Service.unloadPlugin("lifetime-fixture", true, function (receipt) {
      root.retired = receipt.status !== "failed";
    });
    phase = "mutated";
  } else {
    check(session.applySettings(), "native Apply admitted");
    if (scenario === "destroy-busy") {
      check(session.busy && nativeEditor.busy, "presentation destroyed during actual native busy request");
      session.destroy();
      page.destroy();
      session = null;
      page = null;
      phase = "destroyed";
    } else
      phase = "held";
  }
}
function closeRetained() {
  check(session.page === page && page.labelText === "local", "exact local page/input readable");
  check(session.fields.field("label").value === "local", "native local field remains readable");
  check(!session.requestClose(), "failed dirty Close refuses");
  check(session.confirmDiscard(), "only explicit Discard admitted");
  session.presentationClosed();
  page.destroy();
  page = null;
  phase = "discarded";
  deadline = Date.now() + 18000;
}
function finish() {
  console.log("PLUGIN_SETTINGS_LIFETIME: PASS", scenario, family);
  Qt.exit(0);
}
function reopenPreview() {
  phase = "replacement-opening";
  replacementEditor = selected.createSettingsEditor(true);
  check(replacementEditor !== null, "replacement native editor admitted");
  replacementEditor.whenReady(function (result) {
    try {
      check(result.status === "opened", "replacement native editor opened");
      replacementPreview = selected.createSettingsPreview(replacementEditor);
      check(replacementPreview !== null && replacementPreview.update({
                                                                       label: "replacement-preview"
                                                                     }), "replacement preview admission reclaimed");
      phase = "replacement-preview";
    } catch (error) {
      fail(error);
    }
  });
}
function drive() {
  if (deadline && Date.now() > deadline)
    throw new Error("LIFETIME_ASSERT: deadline " + scenario + "/" + family + "/" + phase + ", selected=" + selected?.settingsReady + ":" + selected?.settingsError + ", sibling=" + sibling?.settingsReady + ":" + sibling?.settingsError + ", settled=" + settled() + ", mainReady=" + Settings.store.ready + ", baseReady=" + api?.settingsHandle?.ready
                    + ", baseInfo=" + JSON.stringify(api?.settingsHandle?.info(["label"])));
  if (phase === "runtime") {
    if (family !== "shared" && (!selected.settingsReady || !sibling.settingsReady || !settled()))
      return;
    if (cold) {
      check(selectedText.text === Quickshell.env("PHA_LIFETIME_EXPECTED"), "separate cold bound selected consumer");
      if (sibling)
        check(siblingText.text === (scenario === "reorder" ? "base" : "sibling"), "cold sibling identity");
      console.log("PLUGIN_SETTINGS_LIFETIME: COLD_PASS", scenario, family);
      Qt.exit(0);
    } else
      root.open();
  } else if (phase === "chain-shared") {
    if (sharedText.text !== "local" || selectedText.text !== "local")
      return;
    check(siblingText.text === "sibling" && api.pluginSettings.label === "base", "shared preview inherits below stored sibling override without publication");
    session = sessionFactory.createObject(root);
    check(session.openInstanceSettings(manifest, selected), "concurrent selected session admitted");
    phase = "chain-opening";
  } else if (phase === "chain-instance") {
    if (selectedText.text !== "instance-preview")
      return;
    check(sharedText.text === "local" && siblingText.text === "sibling", "selected preview wins only in its instance");
    check(sharedPage.change("shared-next"), "shared preview can evolve independently");
    phase = "chain-next";
  } else if (phase === "chain-next") {
    if (sharedText.text !== "shared-next")
      return;
    check(selectedText.text === "instance-preview" && siblingText.text === "sibling", "shared update cannot overwrite instance preview or stored sibling override");
    check(session.confirmDiscard(), "explicit instance preview discard");
    session.presentationClosed();
    page.destroy();
    session = sharedSession;
    page = sharedPage;
    phase = "chain-inherit";
  } else if (phase === "chain-inherit") {
    if (selectedText.text !== "shared-next")
      return;
    check(session.confirmDiscard(), "explicit shared preview discard");
    session.presentationClosed();
    page.destroy();
    phase = "chain-base";
  } else if (phase === "chain-base") {
    if (selectedText.text !== "base" || sharedText.text !== "base")
      return;
    check(siblingText.text === "sibling" && receipts === 0 && acknowledgments === 0, "discarded preview chain never publishes or acknowledges");
    finish();
  } else if (phase === "preview") {
    if (selectedText.text !== "local")
      return;
    if (sibling)
      check(siblingText.text === "sibling" && sharedText.text === "base", "placement preview isolation and stored sibling precedence");
    mutate();
  } else if (phase === "mutated") {
    check(page.labelText === "local" && session.fields.field("label").value === "local", "external intent never thaws captured input");
    check(session.applySettings(), "old selected Apply returns truthful failure");
    phase = scenario === "source-replace" && family === "shared" ? "equal-source-accepted" : "refused";
  } else if (phase === "equal-source-accepted" && !session.busy) {
    check(!session.failed && acknowledgments === 1 && receipts === 1 && page.lastStatus === "saved", "shared draft accepts equal-content source replacement at its path fence");
    check(session.requestClose(), "acknowledged shared draft Close admitted");
    session.presentationClosed();
    page.destroy();
    phase = "discarded";
  } else if (phase === "refused" && !session.busy) {
    check(session.failed && acknowledgments === 0 && page.lastStatus === "failed", "conflict/owner failure never acknowledges input");
    check(receipts === 1, "one terminal failure receipt");
    closeRetained();
  } else if (phase === "held" && held) {
    check(session.busy && acknowledgments === 0 && receipts === 0 && heldResult.status === "saved" && heldResult.refreshState === "current", "real current receipt held before acknowledgment");
    check(!session.requestClose() && !session.confirmDiscard(), "busy actions refuse");
    if (scenario === "destroy-delayed" || scenario === "release-delayed") {
      if (scenario === "destroy-delayed")
        session.destroy();
      else
        session.presentationClosed();
      page.destroy();
      if (scenario === "destroy-delayed")
        session = null;
      page = null;
      phase = "deliver-destroyed";
    } else {
      page.labelText = "newer-input";
      var complete = held;
      held = null;
      complete();
      // A saved/current write completes only after the runtime reader has
      // observed it; the terminal receipt arrives on a later turn.
      phase = "held-observing";
      deadline = Date.now() + 15000;
    }
  } else if (phase === "held-observing" && !session.busy) {
    check(acknowledgments === 1 && receipts === 1 && session.dirty && page.labelText === "newer-input", "held current receipt preserves newer buffered input");
    check(!session.requestClose(), "newer local input still requires Discard");
    check(session.confirmDiscard(), "newer buffer discarded explicitly");
    session.presentationClosed();
    phase = "discarded";
  } else if (phase === "deliver-destroyed") {
    var callback = held;
    held = null;
    var deliveryError = false;
    try {
      callback();
    } catch (error) {
      deliveryError = true;
    }
    check(!deliveryError && receipts === 0 && acknowledgments === 0, "late callback cannot reach released selection");
    phase = "destroyed";
  } else if (phase === "destroyed") {
    if (nativeEditor && !nativeEditor.closed)
      return;
    check(receipts === 0 && acknowledgments === 0, "native deferred release suppresses delivery");
    phase = "discarded";
  } else if (phase === "discarded") {
    if (scenario === "unload") {
      if (!retired)
        return;
      check(Service.getPluginAPI("lifetime-fixture") === null, "actual unload fully retired after explicit release");
    } else {
      if (scenario === "reorder" && !reresolved) {
        // A foreign reorder changes the captured placement incarnation (an
        // equal-identity replace does not): the old API refuses, and a fresh
        // lookup serves the new occupant. The lookup destroys the refused API,
        // so check it first.
        if (selected.settingsError !== "overlay-identity")
          return;
        check(!selected.settingsReady, "old placement incarnation retires its runtime context");
        check(selected.settingsPreviewOwner._token === null, "no session preview or admission leaks after release");
        var refused = selected;
        selected = PluginInstances.apiFor("lifetime-fixture", placement);
        sibling = PluginInstances.apiFor("lifetime-fixture", Object.assign({}, placement, {
                                                                             index: 1
                                                                           }));
        check(selected !== null && selected !== refused, "fresh API for the new placement incarnation");
        reresolved = true;
      }
      var expected = scenario === "base-change" ? "foreign" : scenario === "source-change" ? "foreign-source" : scenario === "reorder" ? "sibling" : scenario === "replace" ? "replacement" : (["held", "destroy-delayed", "destroy-busy", "release-delayed"].indexOf(scenario) !== -1 || (scenario === "source-replace" && family === "shared")) ? "local" : "base";
      if (selectedText.text !== expected)
        return;
      check(selected.settingsPreviewOwner._token === null, "no session preview or admission leaks after release");
    }
    if (scenario === "unload")
      finish();
    else
      reopenPreview();
  } else if (phase === "replacement-preview" && selectedText.text === "replacement-preview") {
    check(replacementPreview.close() && replacementEditor.discard(), "replacement preview can close independently");
    phase = "replacement-closed";
  } else if (phase === "replacement-closed" && selectedText.text !== "replacement-preview") {
    finish();
  }
}
Process {
  id: sourceMutation
  command: ["python3", "-B", Quickshell.env("PHA_LIFETIME_MUTATOR"), Settings.configDir + "settings/plugins/lifetime-fixture.json", root.scenario === "source-change" ? "change" : "equal"]
  onExited: code => {
    try {
      check(code === 0, "equal-byte inode replacement fixture");
      phase = "mutated";
    } catch (error) {
      fail(error);
    }
  }
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
  interval: 65000
  running: true
  onTriggered: root.fail("lifetime outer deadline " + root.phase)
}
Component.onCompleted: begin()
}
