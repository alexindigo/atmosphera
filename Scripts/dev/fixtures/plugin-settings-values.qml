import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  property var api: null
  property var selected: null
  property var inherited: null
  property var sibling: null
  property var manifest: null
  property bool started: false
  property bool baseSaved: false
  property string phase: "initial"
  property string afterProbe: ""
  property string probed: ""
  property int receiptCount: 0
  property int receiptFence: 0
  property var lastResult: null
  readonly property string family: Quickshell.env("PHA_VALUES_FAMILY")
  readonly property bool sharedScope: family === "shared"
  readonly property bool cold: Quickshell.env("PHA_VALUES_COLD") === "1"
  readonly property string coldBoundary: Quickshell.env("PHA_VALUES_BOUNDARY") || (sharedScope ? "reset" : "inherited")
  readonly property var keys: ["flag", "amount", "label", "optionalLabel", "items", "record"]
  readonly property var placement: family === "monitor-bar" ? {
                                                                kind: "bar",
                                                                list: "values-screen",
                                                                section: "left",
                                                                index: 0
                                                              } : family === "control-center" ? {
    kind: "controlCenter",
    section: "left",
    index: 0
  } : family === "desktop" ? {
    kind: "desktop",
    screenName: "values-screen",
    index: 0
  } : {
  kind: "bar",
  list: "global",
  section: "left",
  index: 0
}
FileView {
  id: manifestFile
  path: Settings.configDir + "plugins/values-fixture/manifest.json"
  blockLoading: true
  printErrors: false
}
FileView {
  id: expectedFile
  path: Quickshell.env("PHA_VALUES_EXPECTATIONS")
  blockLoading: true
  printErrors: false
}
property var expected: null
function check(ok, message) {
  if (!ok)
    throw new Error("VALUES_ASSERT: " + phase + " " + message);
}
function fail(error) {
  console.error(String(error) + "\n" + (error.stack || ""));
  Qt.exit(2);
}
function canonical(value) {
  if (value === undefined)
    return "absent";
  if (value === null || typeof value !== "object")
    return JSON.stringify(value);
  if (Array.isArray(value))
    return "[" + value.map(canonical).join(",") + "]";
  return "{" + Object.keys(value).sort().map(function (key) {
    return JSON.stringify(key) + ":" + canonical(value[key]);
  }).join(",") + "}";
}
function display(value) {
  var result = {};
  for (var key of keys.concat(["untouched"]))
    if (value && value[key] !== undefined)
      result[key] = Settings.store.copyValue(value[key]);
  return canonical(result);
}
function effective(shared) {
  return Object.assign({}, manifest.metadata.defaultSettings, shared);
}
function expectedSelected(boundary) {
  var row = expected[boundary].rows[0];
  return effective(Object.assign({}, expected[boundary].shared, row.instanceSettings || {}));
}
function current(boundary) {
  var shared = effective(expected[boundary].shared);
  var selected = expectedSelected(boundary);
  var sibling = effective(Object.assign({}, expected[boundary].shared, expected[boundary].rows[2].instanceSettings));
  // Independent fixture read oracle for the native recursive-object overlay:
  // this sibling never overrides the record's opaque member. It inherits it
  // from the current base, even though the record is one atomic edit address.
  sibling.record = Object.assign({}, shared.record, expected[boundary].rows[2].instanceSettings.record);
  return sharedText.text === display(shared) && selectedText.text === display(selected) && inheritedText.text === display(shared) && siblingText.text === display(sibling);
}
function begin() {
  if (started || !Settings.isLoaded)
    return;
  started = true;
  manifestFile.waitForJob();
  expectedFile.waitForJob();
  manifest = JSON.parse(manifestFile.text());
  expected = JSON.parse(expectedFile.text());
  Registry.installedPlugins = {
    "values-fixture": manifest
  };
  Service._openSettingsOwner("values-fixture", function (owner) {
    try {
      check(owner !== null, "native owner");
      api = Service.createPluginAPI("values-fixture", manifest, owner, {}, {}, {});
      Service.loadedPlugins = {
        "values-fixture": {
          api: api
        }
      };
      selected = PluginInstances.apiFor("values-fixture", placement);
      inherited = PluginInstances.apiFor("values-fixture", Object.assign({}, placement, {
                                                                           index: 1
                                                                         }));
      sibling = PluginInstances.apiFor("values-fixture", Object.assign({}, placement, {
                                                                         index: 2
                                                                       }));
      phase = cold ? "cold" : "opening";
    } catch (error) {
      fail(error);
    }
  });
}
function open(next) {
  check(host.showDialog(popup), "presentation admitted");
  check(sharedScope ? popup.openPluginSettings(manifest) : popup.openInstanceSettings(manifest, selected), "selected opening admitted");
  phase = next;
}
function edit() {
  var page = popup.settingsPage;
  page.flagControl.toggled(false);
  page.amountControl.submitValue(0);
  page.labelControl.text = "";
  page.labelControl.editCommitted();
  page.optionalControl.text = "";
  page.optionalControl.editCommitted();
  page.atomicControl.clicked();
  check(page.flagField.value === false && page.amountField.value === 0 && page.labelField.value === "" && page.optionalField.present && page.optionalField.value === "", "false zero empty read values preserved");
  for (var key of keys)
    check(page.pluginApi.field(key).pendingIntent === "set", "explicit typed intent " + key);
}
function apply(next) {
  receiptFence = receiptCount;
  check(popup.applySettings(), "native Apply accepted");
  phase = next;
}
function receipt() {
  if (popup.busy || receiptCount === receiptFence)
    return false;
  check(lastResult && ["saved", "nothing_to_save"].indexOf(lastResult.status) !== -1 && lastResult.refreshState === "current" && !popup.saveFailed, "accepted current native receipt");
  return true;
}
function probe(boundary, next) {
  afterProbe = next;
  probed = boundary;
  phase = "probing";
  disk.command = ["python3", "-B", Quickshell.env("PHA_VALUES_DISK"), Settings.configDir.replace(/\/$/, ""), Quickshell.env("PHA_VALUES_EXPECTATIONS"), boundary, Quickshell.env("PHA_VALUES_OUTPUT")];
  disk.running = true;
}
function saveBase(boundary, next) {
  var settings = expected[boundary].shared;
  for (var key of keys.concat(["untouched"]))
    if (settings[key] !== undefined)
      api.pluginSettings[key] = settings[key];
  baseSaved = false;
  phase = next;
  api.saveSettings(function (result) {
    try {
      check(result.status !== "failed", "external plugin change saved");
      baseSaved = true;
    } catch (error) {
      fail(error);
    }
  });
}
function drive() {
  if (phase === "cold" && current(coldBoundary)) {
    check(!api.settingsPreviewOwner._token && !selected.settingsPreviewOwner._token, "cold consumers have no leaked preview");
    check(!popup.currentPlugin && receiptCount === 0, "cold reader never opens a page or publishes");
    var expectedOptional = (sharedScope ? effective(expected[coldBoundary].shared) : expectedSelected(coldBoundary)).optionalLabel;
    check((sharedScope ? api.settingsView : selected.settingsView).optionalLabel === expectedOptional, "cold optional presence versus empty");
    console.log("PLUGIN_SETTINGS_VALUES: COLD_PASS " + family + " " + coldBoundary);
    Qt.exit(0);
  } else if (phase === "opening" && selected?.settingsReady && inherited?.settingsReady && sibling?.settingsReady && current("initial")) {
    open("page");
  } else if (phase === "page" && popup.opened && popup.settingsPage) {
    check(!popup.dirty && !popup._editor.dirty, "construction carries no intent");
    for (var key of keys)
      check(popup.settingsPage.pluginApi.field(key).pendingIntent === "", "untouched field " + key);
    check(!popup.settingsPage.optionalField.present, "optional absence not an empty string");
    probe("initial", "edit");
  } else if (phase === "edit") {
    edit();
    apply("edited");
  } else if (phase === "edited" && receipt() && current("edited")) {
    check(popup.settingsPage.optionalField.present && popup.settingsPage.optionalField.value === "", "explicit optional empty is present");
    probe("edited", "close-edited");
  } else if (phase === "close-edited") {
    check(popup.requestClose(), "clean edited Close");
    phase = "base-untouched";
  } else if (phase === "base-untouched" && !popup.visible && !popup.currentPlugin) {
    saveBase("untouched", "untouched");
  } else if (phase === "untouched" && baseSaved && current("untouched")) {
    probe("untouched", "reopen-reset");
  } else if (phase === "reopen-reset") {
    open("reset-page");
  } else if (phase === "reset-page" && popup.opened && popup.settingsPage) {
    popup.settingsPage.resetControl.clicked();
    phase = "reset-staging";
  } else if (phase === "reset-staging" && !popup._editor.busy && keys.every(function (key) {
    return popup.settingsPage.pluginApi.field(key).pendingIntent === "reset";
  })) {
    check(!popup.settingsPage.optionalField.present, "optional Reset presents absence");
    check(display(popup.settingsPage.pluginApi.pluginSettings) === display(sharedScope ? effective(expected.reset.shared) : expectedSelected("reset")), "all typed Reset presentations show inherited values");
    for (var key of keys)
      check(popup.settingsPage.pluginApi.field(key).overridden, "staged Reset does not misreport stored override removal " + key);
    probe("reset-staged", "reset-apply");
  } else if (phase === "reset-apply") {
    apply("reset");
  } else if (phase === "reset" && receipt() && current("reset")) {
    for (var key of keys)
      check(!popup.settingsPage.pluginApi.field(key).overridden, "Reset receipt confirms override removal " + key);
    probe("reset", sharedScope ? "finish" : "second");
  } else if (phase === "second") {
    edit();
    apply("second-wait");
  } else if (phase === "second-wait" && receipt() && current("second")) {
    probe("second", "close-second");
  } else if (phase === "close-second") {
    check(popup.requestClose(), "clean second Close");
    phase = "base-equal";
  } else if (phase === "base-equal" && !popup.visible && !popup.currentPlugin) {
    saveBase("base-equal", "base-equal-wait");
  } else if (phase === "base-equal-wait" && baseSaved && current("base-equal")) {
    probe("base-equal", "reopen-equal");
  } else if (phase === "reopen-equal") {
    open("equal-page");
  } else if (phase === "equal-page" && popup.opened && popup.settingsPage) {
    edit();
    apply("equal-wait");
  } else if (phase === "equal-wait" && receipt() && current("equal-omitted")) {
    for (var key of keys)
      check(!popup.settingsPage.pluginApi.field(key).overridden, "equal override omitted " + key);
    probe("equal-omitted", "close-equal");
  } else if (phase === "close-equal") {
    check(popup.requestClose(), "clean equal Close");
    phase = "base-next";
  } else if (phase === "base-next" && !popup.visible && !popup.currentPlugin) {
    saveBase("inherited", "inherited");
  } else if (phase === "inherited" && baseSaved && current("inherited")) {
    probe("inherited", "finish");
  } else if (phase === "finish") {
    if (popup.visible)
      check(popup.requestClose(), "final clean Close");
    console.log("PLUGIN_SETTINGS_VALUES: PASS " + family);
    Qt.exit(0);
  }
}
Text {
  id: sharedText
  text: root.api ? root.display(root.api.settingsView) : ""
}
Text {
  id: selectedText
  text: root.selected ? root.display(root.selected.settingsView) : ""
}
Text {
  id: inheritedText
  text: root.inherited ? root.display(root.inherited.settingsView) : ""
}
Text {
  id: siblingText
  text: root.sibling ? root.display(root.sibling.settingsView) : ""
}
PopupMenuWindow {
  id: host
  shellScreen: Quickshell.screens[0]
  NPluginSettingsPopup {
    id: popup
    parent: host.dialogParent
    screen: host.shellScreen
    onSettingsCompleted: result => {
      root.lastResult = result;
      root.receiptCount++;
    }
  }
}
Process {
  id: disk
  onExited: code => {
    try {
      root.check(code === 0, "independent persisted boundary " + root.probed);
      root.phase = root.afterProbe;
    } catch (error) {
      root.fail(error);
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
  interval: 40
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
  interval: 120000
  running: true
  onTriggered: root.fail("VALUES_ASSERT: watchdog " + root.phase)
}
Component.onCompleted: begin()
}
