// Actual catalog desktop pages -> actual live Popup -> selected owner/file/restart.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Services.Plugins
import qs.Services.UI

PanelWindow {
  id: root
  implicitWidth: 1050
  implicitHeight: 750
  property bool started: false
  property bool iconsReady: false
  property int index: -1
  property var cases: []
  property var page: null
  property var dialog: null
  property string phase: "initial"
  property var fields: ({})
  property var expected: ({})
  property string expectedKey: ""
  property int emissions: 0
  property int ownerIndex: 0
  property var sharedBytes: ({})
  property bool faultBlocked: false
  property bool exitAfterRepair: false
  readonly property var screenObject: Quickshell.screens[0]
  readonly property bool verifyOnly: Quickshell.env("I4_VERIFY") === "1"
  Item {
    id: scene
    anchors.fill: parent
  }
  Component {
    id: inertWidget
    Item {}
  }
  QtObject {
    id: popupHost
    readonly property var dialogParent: scene
    function hideDynamicMenu() {
    }
    function showDialog(value) {
      root.dialog = value;
    }
  }
  FileView {
    id: inputs
    path: Quickshell.env("I4_LIVE_INPUTS")
    blockLoading: true
  }
  FileView { id: sharedFile; blockLoading: true; printErrors: false }
  function checkShared(name) {
    sharedFile.path = Quickshell.env("ATMOSPHERA_CONFIG_DIR") + "/settings/plugins/" + name + ".json";
    sharedFile.reload(); sharedFile.waitForJob();
    var text = sharedFile.text();
    check(JSON.parse(text).sharedSentinel === true, "raw shared sentinel retained");
    if (sharedBytes[name] === undefined) sharedBytes[name] = text;
    check(text === sharedBytes[name], "selected edit leaves shared preference bytes unchanged");
  }
  FileView {
    path: Quickshell.env("I4_ICON_DATA")
    onLoaded: {
      IconRegistry.register("fixture:atmosphera-icons", JSON.parse(text()), Quickshell.env("I4_ICON_DIR"));
      root.iconsReady = true;
      root.begin();
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("I4_DESKTOP_FIELDS_ASSERT: " + message);
  }
  function fail(error) {
    console.error(String(error));
    if (faultBlocked && !faultProcess.running) {
      exitAfterRepair = true;
      fault("repair");
      return;
    }
    Qt.callLater(function () {
      Qt.exit(2);
    });
  }
  function later(callback) {
    Qt.callLater(function () {
      try {
        callback();
      } catch (error) {
        fail(error);
      }
    });
  }
  function kind(item, name) {
    return String(item).indexOf(name + "_QMLTYPE") === 0;
  }
  function find(item, predicate) {
    if (predicate(item))
      return item;
    var children = item.children || [];
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], predicate);
      if (found)
        return found;
    }
    return null;
  }
  function control(name, label) {
    var value = find(page, function (item) {
      return kind(item, name) && (!label || item.label === label);
    });
    check(value !== null, "actual control " + cases[index].manifest.id + "/" + name);
    return value;
  }
  function rows() {
    return Settings.data.desktopWidgets.monitorWidgets[0].widgets;
  }
  function initial(item) {
    return {
      id: "plugin:" + item.manifest.id,
      tag: item.manifest.id,
      x: 7,
      y: 9,
      scale: 2,
      opaque: {
        keep: true
      }
    };
  }
  function begin() {
    if (started || !iconsReady || !Settings.isLoaded)
      return;
    try {
      inputs.waitForJob();
      cases = JSON.parse(inputs.text());
      if (cases.some(function (item) {
        return Registry.getPluginManifest(item.manifest.id) === null;
      }))
        return;
      started = true;
      var version = Version.currentVersion, known = Version.versionKnown;
      try {
        Version.versionKnown = true;
        Version.currentVersion = "0.9.1";
        cases.forEach(function (item) {
          check(!Service.checkPluginCompatibility(item.manifest).compatible, "live field producer requires0.10");
        });
        Version.currentVersion = "0.10.0";
        cases.forEach(function (item) {
          check(Service.checkPluginCompatibility(item.manifest).compatible, "selected release admits live producer");
        });
      } finally {
        Version.currentVersion = version;
        Version.versionKnown = known;
      }
      phase = "owners";
      openNextOwner();
    } catch (error) {
      fail(error);
    }
  }
  function openNextOwner() {
    if (ownerIndex === cases.length) { ownersReady(); return; }
    var item = cases[ownerIndex];
    if (verifyOnly) { openOwner(item); return; }
    seedWriter.command = ["python3", "-B", Quickshell.env("I5_PLUGIN_SEED"), Quickshell.env("ATMOSPHERA_CONFIG_DIR"), item.manifest.id, JSON.stringify({sharedSentinel: true})];
    seedWriter.running = true;
  }
  function openOwner(item) {
    Service._openSettingsOwner(item.manifest.id, function (owner) {
      try {
        root.check(owner !== null, "actual shared owner opened");
        var api = Service.createPluginAPI(item.manifest.id, item.manifest, owner, {}, {}, {});
        var loaded = Object.assign({}, Service.loadedPlugins);
        loaded[item.manifest.id] = {api: api};
        Service.loadedPlugins = loaded;
        root.check(DesktopWidgetRegistry.registerPluginWidget(item.manifest.id, inertWidget, item.manifest.metadata?.defaultSettings || {}), "register actual placement metadata");
        root.checkShared(item.manifest.id);
        root.ownerIndex++;
        root.openNextOwner();
      } catch (error) { root.fail(error); }
    });
  }
  function ownersReady() {
    PanelService.registerPopupMenuWindow(screenObject, popupHost);
    if (verifyOnly) {
      finalChecks();
      console.log("I4_DESKTOP_FIELDS: RESTART_PASS");
      Qt.callLater(function () { Qt.exit(0); });
      return;
    }
    Settings.data.desktopWidgets.monitorWidgets = [
            {
              name: screenObject.name,
              opaque: "monitor",
              widgets: cases.map(initial)
            },
            {
              name: screenObject.name,
              opaque: "duplicate",
              widgets: [
                {
                  id: "Clock",
                  tag: "duplicate"
                }
              ]
            }
          ];
    next();
  }
  function next() {
    index++;
    page = null;
    dialog = null;
    fields = {};
    emissions = 0;
    phase = "waiting-placement";
    if (index === cases.length) {
      finish();
      return;
    }
  }
  Timer {
    interval: 20
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
  function drive() {
    if (phase === "waiting-placement") {
      var editor = DesktopWidgetRegistry.createWidgetSettingsEditor(screenObject.name, index);
      if (!editor) return;
      phase = "opening";
      DesktopWidgetRegistry.openWidgetSettings(screenObject, index, "plugin:" + cases[index].manifest.id,
        rows()[index], undefined, undefined, undefined, undefined, undefined, editor);
    } else if (phase === "opening" && dialog && dialog.visible) {
      page = find(dialog.contentItem, function (item) {
        return item.widgetSettings !== undefined && typeof item.saveSettings === "function";
      });
      if (!page)
        return;
      check(typeof page.settingsChanged === "function", "actual live page exposes field intent");
      page.settingsChanged.connect(record);
      phase = "untouched";
      settled.start();
    } else if (phase === "closing" && DesktopWidgetRegistry.currentSettingsDialog === null) {
      checkRow();
      next();
    }
  }
  Timer {
    id: settled
    interval: 120
    onTriggered: {
      try {
        root.untouched();
      } catch (error) {
        root.fail(error);
      }
    }
  }
  function record(patch) {
    try {
      check(phase === "action" || phase === "retry", "no constructor/programmatic/close field intent");
      check(Object.keys(patch).join(',') === expectedKey, "exact user field only " + expectedKey + " " + JSON.stringify(patch));
      fields = Object.assign({}, fields, patch);
      emissions++;
    } catch (error) {
      fail(error);
    }
  }
  function untouched() {
    page.saveSettings();
    check(!dialog.settingsDirty, "constructor has no queued/native input");
    check(emissions === 0, "untouched page has no preference input");
    checkRow();
    var old = page.widgetSettings;
    page.widgetSettings = {
      data: old.data,
      metadata: Object.assign({}, old.metadata, {
                                unrelatedMetadata: true
                              }),
      save: old.save
    };
    if (cases[index].manifest.id === "hello-world") {
      var input = control("NTextInput", "");
      input.text = "";
      check(emissions === 0, "programmatic text does not submit");
    }
    phase = "blocking";
    fault("block");
  }
  function fault(mode) {
    faultProcess.command = ["python3", "-B", Quickshell.env("I5_DESKTOP_FAULT"), Quickshell.env("ATMOSPHERA_CONFIG_DIR"), mode];
    faultProcess.running = true;
  }
  function action() {
    var item = cases[index];
    expectedKey = item.key;
    if (item.kind === "NTextInput")
      control(item.kind, "").inputItem.insert(0, phase === "retry" ? "desktop-newer" : "desktop-first");
    else if (item.kind === "NToggle")
      control(item.kind, item.label || "").toggled(item.value);
    else
      control(item.kind, item.label || "").selected(item.value);
  }
  Connections {
    target: root.dialog
    ignoreUnknownSignals: true
    function onSettingsSaveCompleted(result) {
      root.receipt(result);
    }
  }
  function receipt(result) {
    try {
      console.log("I4_DESKTOP_RECEIPT", cases[index].manifest.id, phase, JSON.stringify(result));
      if (phase === "action") {
        check(result.status === "failed" && dialog.visible && dialog.settingsDirty, "failed live input retained");
        dialog.requestDiscard();
        check(dialog.discardPending, "failed discard asks");
        dialog.keepEditing();
        check(!dialog.discardPending && dialog.settingsDirty, "keep editing retains failed input");
        phase = "repairing";
        fault("repair");
      } else if (phase === "retry") {
        check(result.status !== "failed", "actual current Retry receipt");
        expected[cases[index].manifest.id] = Object.assign({}, fields);
        phase = "closing";
      }
    } catch (error) {
      fail(error);
    }
  }
  function checkRow() {
    var row = rows()[index], want = Object.assign(initial(cases[index]), fields);
    check(Object.keys(row).sort().join(',') === Object.keys(want).sort().join(','), "only selected user fields " + cases[index].manifest.id);
    Object.keys(want).forEach(function (key) {
      check(JSON.stringify(row[key]) === JSON.stringify(want[key]), "unknown placement preserved / explicit field " + key);
    });
    checkShared(cases[index].manifest.id);
  }
  function finalChecks() {
    var monitors = Settings.data.desktopWidgets.monitorWidgets;
    check(monitors.length === 2 && monitors[0].opaque === "monitor" && monitors[1].opaque === "duplicate" && monitors[1].widgets[0].tag === "duplicate", "ancestry and duplicate monitors retained");
    check(rows().length === cases.length, "all eight live rows");
    cases.forEach(function (item, n) {
      checkShared(item.manifest.id);
      var row = rows()[n];
      check(row.tag === item.manifest.id && row.opaque.keep && row.x === 7 && row.y === 9 && row.scale === 2, "placement fields unchanged");
      check(row[item.key] === (item.kind === "NTextInput" ? "desktop-newer" : item.value), "restarted actual placement consumer " + item.manifest.id);
      check(Object.keys(row).sort().join(',') === Object.keys(Object.assign(initial(item), {
                                                                              [item.key]: item.value
                                                                            })).sort().join(','), "no untouched defaults materialized");
    });
  }
  function finish() {
    phase = "finish";
    Settings.saveResult(function (result) {
      try {
        check(result.status !== "failed", "final persistence receipt");
        finalChecks();
        console.log("I4_DESKTOP_FIELDS: SAVED_PASS");
        Qt.callLater(function () {
          Qt.exit(0);
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
  Connections {
    target: Registry
    function onPluginsChanged() {
      root.begin();
    }
  }
  Process {
    id: faultProcess
    onExited: code => {
      try {
        root.check(code === 0, "private directory permission prerequisite");
        if (root.phase === "blocking") {
          root.faultBlocked = true;
          root.phase = "action";
          root.action();
          root.check(root.emissions === 1, "one native control signal / one field intent");
        } else {
          root.faultBlocked = false;
          if (root.exitAfterRepair) { Qt.exit(2); return; }
          root.phase = "retry";
          if (root.cases[root.index].kind === "NTextInput") root.control("NTextInput", "").text = "";
          root.action();
          root.dialog.saveAndClose();
        }
      } catch (error) { root.fail(error); }
    }
  }
  Process {
    id: seedWriter
    onExited: code => {
      try {
        root.check(code === 0, "private original shared preference seed");
        root.openOwner(root.cases[root.ownerIndex]);
      } catch (error) { root.fail(error); }
    }
  }
  Component.onCompleted: begin()
  Timer {
    interval: 90000
    running: true
    onTriggered: root.fail("desktop field watchdog " + phase + "/" + index)
  }
}
