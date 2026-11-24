// Actual Main, views, generic page and native files; controlled observation only.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_POLL_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_POLL_SCOPE")
  readonly property string mode: Quickshell.env("PHA_POLL_MODE")
  readonly property string boundary: Quickshell.env("PHA_POLL_BOUNDARY")
  readonly property bool oldRed: Quickshell.env("PHA_POLL_OLD_RED") === "1"
  readonly property bool wireless: plugin === "battery-wireless-devices"
  readonly property int unit: wireless ? 1000 : 1
  readonly property int editValue: wireless ? 10 : 1000
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var sibling: null
  property var inherited: null
  property var main: null
  property var presentations: []
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property var retiredClients: []
  property string busyRequests: ""
  FileView {
    id: requestsFile
    path: Quickshell.env("PHA_POLL_CASE") + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/" + root.plugin + "/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/" + root.plugin + "/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: Quickshell.env("PHA_POLL_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("POLL_DISK " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
    Item {
      id: content
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
      throw new Error("POLL_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
  }
  function fail(error) {
    console.error(String(error) + "\n" + (error.stack || ""));
    Qt.exit(2);
  }
  function find(object, predicate) {
    if (object && predicate(object))
      return object;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var result = find(child, predicate);
        if (result)
          return result;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject(plugin, entry, component, content, context, {
                                           screen: Quickshell.screens[0]
                                         });
    check(item !== null, "actual " + entry + " created");
    return item;
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    manifestFile.waitForJob();
    dictionaryFile.waitForJob();
    var manifest = JSON.parse(manifestFile.text()), dictionary = JSON.parse(dictionaryFile.text());
    var registry = {};
    registry[plugin] = manifest;
    Registry.installedPlugins = registry;
    Service._openSettingsOwner(plugin, function (owner) {
      try {
        check(owner !== null, "native owner");
        api = Service.createPluginAPI(plugin, manifest, owner, dictionary, dictionary, {});
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        var instances = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                        kind: "bar",
                                                                        list: "global",
                                                                        section: "left",
                                                                        index: index
                                                                      }));
        selected = instances[0];
        sibling = instances[1];
        inherited = instances[2];
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expectedFile.reload();
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name];
    var base = Object.assign({}, api.manifest.metadata.defaultSettings, expected.shared);
    return [base].concat(expected.bar.widgets.left.map(row => Object.assign({}, base, row.instanceSettings || {})));
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every((item, index) => item.api.pluginSettings.refreshInterval === expected[index].refreshInterval);
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = item.bar.settingsConsumer;
      check(client && client === main.settingsConsumerFor(item.api.settingsContext), "Bar has exact captured-context scheduling client");
      check(item.second.settingsConsumer === client && (!item.panel || item.panel.settingsConsumer === client), "all views of one API share one scheduling client");
      check(client.interval === expected[i].refreshInterval * unit, "actual selected Timer interval preserves units");
      var timer = find(client, child => child.repeat === true && child.triggered !== undefined);
      check(timer && timer.interval === client.interval && timer.running, "actual selected Timer is running");
      if (i > 0)
        check(client !== presentations[0].bar.settingsConsumer, "distinct runtime context never shares scheduling client");
    }
    check(main._settingsConsumers.size === 4, "one Main-owned scheduling client per API, never per view");
    console.log("POLL_CONSUMERS " + JSON.stringify({
                                                     plugin: plugin,
                                                     scope: scope,
                                                     mode: mode,
                                                     boundary: name,
                                                     intervals: expected.map(value => value.refreshInterval * unit)
                                                   }));
  }
  function observationReady(value) {
    if (wireless)
      return main.devices.length === 1 && main.devices[0].battery === value;
    return main.warpInstalled && main.warpConnected === value;
  }
  function observeResult() {
    for (var item of presentations) {
      if (wireless) {
        check(item.bar.liveDevices === main.devices && item.bar.shownDevices.length === 1 && item.bar.shownDevices[0].battery === 73, "actual Bar device projection sees shared periodic result");
        var percentage = find(item.bar, child => child.text === "73%");
        check(percentage, "actual child battery Text renders periodic result");
      } else {
        check(item.bar.mainInstance === main && item.panel.mainInstance === main, "physical observation owner remains singular");
        var status = find(item.panel, child => child.text === api.tr("panel.status.connected"));
        check(status, "actual Panel status Text sees periodic result");
      }
    }
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_POLL_DISK"), Quickshell.env("PHA_POLL_CASE"), Quickshell.env("PHA_POLL_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, child => child.objectName === "settings-range-editRefreshInterval");
    check(control, "actual polling control");
    if (wireless)
      control.submitValue(editValue);
    else {
      control.value = editValue;
      control.moved();
    }
    check(popup._pageApi.field("refreshInterval").value === editValue, "real control stages interval intent");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== "refreshInterval")
        check(!popup._pageApi.field(key).pendingIntent, "untouched field has no intent: " + key);
    if (!oldRed) {
      var explanation = find(popup.settingsPage, child => child.text === api.tr("settings.shared-observation"));
      check(explanation && explanation.visible === (scope === "instance"), "truthful shared-observation instance explanation");
    }
  }
  function apply(next) {
    receipt = null;
    check(popup.applySettings(), "native Apply");
    phase = next;
  }
  function accepted() {
    return receipt && !popup.busy && receipt.status === "saved" && receipt.refreshState === "current";
  }
  function drive() {
    check(Date.now() - phaseStarted < 22000, "finite operation deadline");
    if (phase === "runtime" && selected.settingsReady && sibling.settingsReady && inherited.settingsReady) {
      presentations = [api, selected, sibling, inherited].map(context => ({
        api: context,
        bar: create("barWidget", context),
        second: create("barWidget", context),
        panel: wireless ? null : create("panel", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var initial = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(initial) || !wireless && !main.warpInstalled || wireless && !main.devices.length)
        return;
      observe(initial);
      if (mode === "cold") {
        if (boundary !== "initial")
          observeResult();
        console.log("POLL: COLD_PASS " + plugin + " " + scope + " " + boundary);
        Qt.exit(0);
      } else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "page construction has no intent");
      edit();
      observe("initial");
      check(!popup.requestClose(), "dirty Close refuses");
      popup.confirmDiscard();
      phase = "discarded";
    } else if (phase === "discarded" && !popup.opened && !popup._editor)
      probe("discarded", "open-edit");
    else if (phase === "open-edit")
      open("edit-page");
    else if (phase === "edit-page" && popup.opened && popup.settingsPage) {
      edit();
      apply("applied");
    } else if (phase === "applied" && accepted() && ready("edited")) {
      observe("edited");
      probe("edited", "periodic");
    } else if (phase === "periodic") {
      if (oldRed) {
        var timer = find(main, child => child.repeat === true && child.triggered !== undefined);
        check(timer && timer.interval === editValue * unit, "old actual polling Timer follows saved instance interval");
        throw new Error("old polling defect did not reproduce");
      }
      if (!observationReady(wireless ? 73 : true))
        return;
      observeResult();
      if (!wireless) {
        main.warpInstalled = false;
        check(presentations.every(item => !item.bar.settingsConsumer.running), "installed guard disables every schedule");
        main.warpInstalled = true;
        requestsFile.reload();
        requestsFile.waitForJob();
        busyRequests = requestsFile.text();
        main.isRefreshing = true;
        phase = "busy-blocked";
        return;
      }
      probe("edited", "finish");
    } else if (phase === "busy-blocked" && Date.now() - phaseStarted > 2200) {
      requestsFile.reload();
      requestsFile.waitForJob();
      check(requestsFile.text() === busyRequests, "busy guard prevents overlapping observation requests from actual scheduled ticks");
      main.isRefreshing = false;
      probe("edited", "finish");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("refreshInterval").reset(), "staged polling Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.refreshInterval = wireless ? 180 : 180000;
      phase = "base-saving";
      api.saveSettings(function (result) {
        try {
          check(result.status === "saved", "native shared propagation");
          phase = "base-changed";
        } catch (error) {
          fail(error);
        }
      });
    } else if (phase === "base-changed" && ready("following")) {
      observe("following");
      probe("following", "retire");
    } else if (phase === "retire") {
      retiredClients = presentations.map(item => item.bar.settingsConsumer);
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => item.bar.settingsConsumer === null && item.second.settingsConsumer === null && (!item.panel || item.panel.settingsConsumer === null)), "retired context leaves no cached schedule or view client");
      phase = "finish";
    } else if (phase === "finish") {
      console.log("POLL: PASS " + plugin + " " + scope + " " + mode);
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
  Component.onCompleted: begin()
}
