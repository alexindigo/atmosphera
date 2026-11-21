import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_BATTERY_SCOPE")
  readonly property bool cold: Quickshell.env("PHA_BATTERY_COLD") === "1"
  readonly property string caseRoot: Quickshell.env("PHA_BATTERY_CASE")
  property bool started: false
  property string phase: "startup"
  property string next: ""
  property var api: null
  property var main: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var rows: []
  property var receipt: null
  property var failedPage: null
  property var failedEditor: null
  property int coldIndex: 0
  property var retiringDevice: null
  property string writeValue: "65"
  FileView {
    id: enteredFile
    path: root.caseRoot + "/write-entered-" + root.writeValue
    printErrors: false
  }
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/battery-threshold/manifest.json"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/battery-threshold/i18n/en.json"
    blockLoading: true
    printErrors: false
  }
  Process {
    id: disk
    stdout: StdioCollector {
      onStreamFinished: console.log(text)
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text)
          console.error(text);
      }
    }
    onExited: function (code) {
      if (code !== 0)
        root.fail("independent disk boundary failed");
      else
        root.phase = root.next;
    }
  }
  Process {
    id: actor
    onExited: function (code) {
      if (code !== 0)
        root.fail("permission actor failed");
      else
        root.phase = root.next;
    }
  }
  PanelWindow {
    implicitWidth: 1280
    implicitHeight: 850
    Item {
      id: consumerHost
      width: 1280
      height: 800
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("BATTERY_ASSERT: " + scope + "/" + phase + " " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    console.error("BATTERY_FAILURE_STATE " + JSON.stringify({
                                                              receipt: receipt,
                                                              rows: rows.map(function (row) {
                                                                const client = row.panel.service;
                                                                return {
                                                                  device: client?.batteryDevice,
                                                                  ownerDevice: client?.device?.batteryDevice,
                                                                  threshold: client?.currentThreshold,
                                                                  ready: client?.device?.ready,
                                                                  busy: client?.busy,
                                                                  writable: client?.isWritable,
                                                                  restoreRequested: client?._restoreRequested,
                                                                  expectedDevice: client?._expectedRestoreDevice,
                                                                  restoredPolicy: client?._restoredPolicy,
                                                                  policy: client?.policy,
                                                                  actionError: client?.actionError
                                                                };
                                                              })
                                                            }));
    Qt.exit(2);
  }
  function find(item, predicate) {
    if (item && predicate(item))
      return item;
    for (var list of [item?.data, item?.children, item?.resources]) {
      if (!list)
        continue;
      for (var i = 0; i < list.length; i++) {
        var found = find(list[i], predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, parent, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("battery-threshold", entry, component, parent, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(!!item, "actual " + entry);
    return item;
  }
  function makeRow(context, index) {
    const panel = create("panel", consumerHost, context);
    panel.x = index * 315;
    panel.width = 310;
    panel.height = 700;
    const bar = create("barWidget", consumerHost, context);
    bar.y = 710;
    bar.x = index * 315;
    return {
      api: context,
      panel: panel,
      bar: bar
    };
  }
  function makeRows() {
    rows = [api, selected, sibling, inherited].map(makeRow);
  }
  function ready(expectedDevices, expectedValues) {
    for (var i = 0; i < rows.length; i++) {
      const row = rows[i];
      const client = main.settingsConsumerFor(row.api.settingsContext);
      check(client.settingsContext === row.api.settingsContext, "Main must retain selected runtime context");
      check(row.panel.service === client && row.bar.service === client, "Panel/Bar must use exact selected client");
      if (!client.isAvailable || !client.isWritable || client.busy || client.batteryDevice !== caseRoot + "/devices/" + expectedDevices[i] || client.currentThreshold !== expectedValues[i])
        return false;
      if (row.panel.batteryModelName !== "Synthetic " + expectedDevices[i])
        return false;
      check(find(row.panel, item => item !== row.panel && item.font !== undefined && item.text === expectedValues[i] + "%") !== null, "actual child Text must render selected physical threshold");
      check(find(row.panel, item => item.text === api.tr("settings.shared-device")) !== null, "physical shared effect is explicit");
    }
    return true;
  }
  function open() {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest) : popup.openInstanceSettings(api.manifest, selected, "settings"), "real selected page opens");
  }
  function choose(name) {
    const combo = find(popup.settingsPage, item => item.label === api.tr("settings.battery-device") && typeof item.selected === "function");
    check(!!combo && combo.visible && combo.enabled, "actual visible enabled battery chooser");
    check(popup.settingsPage.service === main.settingsConsumerFor((scope === "shared" ? api : selected).settingsContext), "page completion uses captured runtime context");
    combo.selected(caseRoot + "/devices/" + name);
    check(popup._pageApi.field("batteryDevice").value === caseRoot + "/devices/" + name, "genuine chooser field intent");
  }
  function apply(nextPhase) {
    receipt = null;
    check(popup.applySettings(), "native Apply admitted");
    phase = nextPhase;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function probe(name, nextPhase) {
    next = nextPhase;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_BATTERY_DISK"), name];
    disk.running = true;
  }
  function chmod(mode, nextPhase) {
    next = nextPhase;
    phase = "actor";
    actor.command = ["chmod", mode, scope === "shared" ? Settings.configDir + "settings/plugins" : Settings.configDir + "settings"];
    actor.running = true;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    const manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    Registry.installedPlugins = {
      "battery-threshold": manifest
    };
    Service._openSettingsOwner("battery-threshold", function (owner) {
      try {
        check(!!owner, "native shared owner");
        api = Service.createPluginAPI("battery-threshold", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "battery-threshold": {
            api: api,
            manifest: manifest
          }
        };
        main = create("main", root, api);
        api.mainInstance = main;
        selected = PluginInstances.apiFor("battery-threshold", {
                                            kind: "bar",
                                            list: "global",
                                            section: "left",
                                            index: 0
                                          });
        sibling = PluginInstances.apiFor("battery-threshold", {
                                           kind: "bar",
                                           list: "global",
                                           section: "left",
                                           index: 1
                                         });
        inherited = PluginInstances.apiFor("battery-threshold", {
                                             kind: "bar",
                                             list: "global",
                                             section: "left",
                                             index: 2
                                           });
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function drive() {
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady && main.batteries.length === 2) {
      if (cold) {
        rows = [makeRow(api, 0)];
        phase = "cold-step";
      } else {
        makeRows();
        phase = "initial";
      }
    } else if (phase === "cold-step") {
      const policies = scope === "shared" ? [65, 65, 80, 65] : [80, 65, 80, 80];
      const devices = ["BAT0", "BAT0", "BAT0", "BAT0"];
      if (!ready(devices, policies.map(() => policies[coldIndex])))
        return;
      for (var i = 0; i < rows.length; i++) {
        check(rows[i].panel.service.cfg.chargeThreshold === policies[i], "cold effective restore policy remains independently scoped");
        if (rows[i].panel.service._restoreRequested)
          return;
      }
      console.log("BATTERY_COLD_RESTORE " + JSON.stringify({
                                                             index: coldIndex,
                                                             policy: policies[coldIndex],
                                                             physical: rows[0].panel.service.currentThreshold
                                                           }));
      coldIndex++;
      if (coldIndex < 4)
        rows = rows.concat([makeRow([api, selected, sibling, inherited][coldIndex], coldIndex)]);
      else
        probe("cold", "cold-finish");
    } else if (phase === "cold-finish") {
      console.log("BATTERY: COLD_PASS " + scope);
      Qt.exit(0);
    } else if (phase === "initial") {
      if (ready(["BAT0", "BAT0", "BAT0", "BAT0"], [80, 80, 80, 80]))
        probe("initial", "ipc-75");
    } else if (phase === "ipc-75" || phase === "ipc-80") {
      const value = phase === "ipc-75" ? "75" : "80";
      next = phase + "-wait";
      phase = "actor";
      actor.command = ["qs", "ipc", "-p", Quickshell.shellDir + "/plugin-settings-battery.qml", "call", "plugin:battery-threshold", "set", value];
      actor.running = true;
    } else if (phase === "ipc-75-wait" || phase === "ipc-80-wait") {
      const value = phase === "ipc-75-wait" ? 75 : 80;
      if (api.pluginSettings.chargeThreshold !== value || api._pendingSettingsSaves !== 0 || !api._lastSettingsSave || api._lastSettingsSave.status !== "saved" || !ready(["BAT0", "BAT0", "BAT0", "BAT0"], [value, value, value, value]))
        return;
      probe(value === 75 ? "ipc75" : "ipc80", value === 75 ? "ipc-80" : "open-discard");
    } else if (phase === "open-discard") {
      open();
      phase = "discard-page";
    } else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      choose("BAT1");
      check(popup.requestClose() === false, "dirty Close refuses");
      check(popup.confirmDiscard(), "explicit Discard");
      probe("discarded", "open-fail");
    } else if (phase === "open-fail") {
      open();
      phase = "fail-page";
    } else if (phase === "fail-page" && popup.opened && popup.settingsPage) {
      choose("BAT1");
      failedPage = popup.settingsPage;
      failedEditor = popup._editor;
      chmod("500", "apply-fail");
    } else if (phase === "apply-fail")
      apply("failed");
    else if (phase === "failed" && receipt && !popup.busy) {
      check(receipt.status === "failed" && receipt.refreshState !== "current", "real IO refusal");
      check(popup.settingsPage === failedPage && popup._editor === failedEditor, "failed editor/input retained");
      // Native shared failure retains the unconfirmed desired API value;
      // inherited placement views and physical bytes remain persisted.
      check(ready(scope === "shared" ? ["BAT1", "BAT0", "BAT0", "BAT0"] : ["BAT0", "BAT0", "BAT0", "BAT0"], scope === "shared" ? [60, 80, 80, 80] : [80, 80, 80, 80]), "failed page cannot restore a physical threshold");
      probe("failed", "unlock");
    } else if (phase === "unlock")
      chmod("700", "retry");
    else if (phase === "retry")
      apply("edited");
    else if (phase === "edited" && accepted() && ready(scope === "shared" ? ["BAT1", "BAT1", "BAT0", "BAT1"] : ["BAT0", "BAT1", "BAT0", "BAT0"], [80, 80, 80, 80])) {
      check(popup.requestClose(), "clean Close");
      probe("edited", "device-refuse");
    } else if (phase === "device-refuse") {
      next = "device-refused-action";
      phase = "actor";
      actor.command = ["touch", caseRoot + "/hold-write-65"];
      actor.running = true;
    } else if (phase === "device-refused-action") {
      const target = scope === "shared" ? api : selected;
      check(main.settingsConsumerFor(target.settingsContext).setThreshold(65, target), "writable observation admits held device operation");
      phase = "device-held";
    } else if (phase === "device-held") {
      enteredFile.reload();
      enteredFile.waitForJob();
      if (!enteredFile.loaded)
        return;
      next = "device-release-failure";
      phase = "actor";
      actor.command = ["chmod", "400", caseRoot + "/devices/BAT1/charge_control_end_threshold"];
      actor.running = true;
    } else if (phase === "device-release-failure") {
      next = "device-failed";
      phase = "actor";
      actor.command = ["touch", caseRoot + "/release-write-65"];
      actor.running = true;
    } else if (phase === "device-failed") {
      const client = main.settingsConsumerFor((scope === "shared" ? api : selected).settingsContext);
      if (client.busy || client.actionError !== "device-write")
        return;
      check(find(rows[scope === "shared" ? 0 : 1].panel, item => item.visible && item.text === api.tr("panel.action-failed")) !== null, "physical failure remains visible");
      probe("device_failed", "device-unlock");
    } else if (phase === "device-unlock") {
      next = "device-reprobe";
      phase = "actor";
      actor.command = ["chmod", "600", caseRoot + "/devices/BAT1/charge_control_end_threshold"];
      actor.running = true;
    } else if (phase === "device-reprobe") {
      main.settingsConsumerFor((scope === "shared" ? api : selected).settingsContext).device.refresh();
      phase = "device-writable";
    } else if (phase === "device-writable" && ready(scope === "shared" ? ["BAT1", "BAT1", "BAT0", "BAT1"] : ["BAT0", "BAT1", "BAT0", "BAT0"], [80, 80, 80, 80]))
      phase = "action";
    else if (phase === "action") {
      const panel = rows[scope === "shared" ? 0 : 1].panel;
      const slider = find(panel, item => typeof item.moved === "function" && item.from === 40 && item.to === 100);
      check(!!slider, "actual threshold slider");
      slider.value = 65;
      slider.moved();
      phase = "acted";
    } else if (phase === "acted") {
      const target = scope === "shared" ? api : selected;
      if (api._pendingSettingsSaves !== 0 || selected._pendingSettingsSaves !== 0 || (!api._lastSettingsSave && !selected._lastSettingsSave) || !ready(scope === "shared" ? ["BAT1", "BAT1", "BAT0", "BAT1"] : ["BAT0", "BAT1", "BAT0", "BAT0"], scope === "shared" ? [65, 65, 80, 65] : [80, 65, 80, 80]))
        return;
      probe("acted", "open-reset");
    } else if (phase === "open-reset") {
      open();
      phase = "reset-page";
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage) {
      check(popup._pageApi.field("batteryDevice").reset(), "native field Reset staged");
      phase = "reset-ready";
    } else if (phase === "reset-ready" && popup._pageApi.field("batteryDevice").value === caseRoot + "/devices/BAT0")
      probe("reset_staged", "reset-apply");
    else if (phase === "reset-apply")
      apply("reset");
    else if (phase === "reset" && accepted() && ready(["BAT0", "BAT0", "BAT0", "BAT0"], [65, 65, 65, 65])) {
      check(popup.requestClose(), "Reset Close");
      probe("reset", "hold-write");
    } else if (phase === "hold-write") {
      writeValue = "70";
      next = "start-retiring-action";
      phase = "actor";
      actor.command = ["touch", caseRoot + "/hold-write-70"];
      actor.running = true;
    } else if (phase === "start-retiring-action") {
      const target = scope === "shared" ? api : selected;
      retiringDevice = main.settingsConsumerFor(target.settingsContext).device;
      check(main.settingsConsumerFor(target.settingsContext).setThreshold(70, target), "captured runtime action admitted");
      phase = "retire-entered";
    } else if (phase === "retire-entered") {
      enteredFile.reload();
      enteredFile.waitForJob();
      if (!enteredFile.loaded)
        return;
      check(retiringDevice.busy && retiringDevice.currentThreshold === 65, "held physical write has not happened");
      Service.loadedPlugins = {};
      phase = "retired";
    } else if (phase === "retired" && main._settingsConsumers.size === 0) {
      check(rows.every(row => row.panel.service === null && row.bar.service === null), "retired contexts have no consumers");
      next = "retired-write";
      phase = "actor";
      actor.command = ["touch", caseRoot + "/release-write-70"];
      actor.running = true;
    } else if (phase === "retired-write" && !retiringDevice.busy && retiringDevice.currentThreshold === 70) {
      probe("retired", "finish");
    } else if (phase === "finish") {
      console.log("BATTERY: PASS " + scope);
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
    interval: 80
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
    interval: 85000
    running: true
    onTriggered: root.fail("BATTERY_ASSERT: watchdog " + phase)
  }
  Component.onCompleted: begin()
}
