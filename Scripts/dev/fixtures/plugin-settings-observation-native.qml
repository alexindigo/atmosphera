// Real page intents/native files joined to actual selected observation children.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_OBSERVATION_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_OBSERVATION_SCOPE")
  readonly property string mode: Quickshell.env("PHA_OBSERVATION_MODE")
  readonly property string boundary: Quickshell.env("PHA_OBSERVATION_BOUNDARY")
  readonly property bool port: plugin === "port-monitor"
  readonly property bool oldRed: Quickshell.env("PHA_OBSERVATION_OLD_RED") === "1"
  readonly property string field: port ? "hideSystemPorts" : "showCityName"
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
  property int actionStep: 0
  property double actionStarted: 0
  FileView {
    id: actionRequests
    path: Quickshell.env("PHA_OBSERVATION_REQUESTS")
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
    path: Quickshell.env("PHA_OBSERVATION_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("independent observation document readback: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 900
    Item {
      id: content
      width: 1280
      height: 900
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OBSERVATION_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
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
    check(item !== null, "actual " + entry + " constructs");
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
        check(owner !== null, "actual native plugin owner");
        api = Service.createPluginAPI(plugin, manifest, owner, dictionary, dictionary, {});
        var loaded = {};
        loaded[plugin] = {
          api: api
        };
        Service.loadedPlugins = loaded;
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor(plugin, {
                                                                       kind: "bar",
                                                                       list: "global",
                                                                       section: "left",
                                                                       index: index
                                                                     }));
        selected = contexts[0];
        sibling = contexts[1];
        inherited = contexts[2];
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
    return presentations.every((item, index) => item.api.pluginSettings[field] === expected[index][field]) && (port ? (oldRed ? main.portCount === 3 : main.rawPorts.length === 3) : main.state === "connected");
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext);
      check((port ? item.bar.mainInstance : item.bar.main) === client && (port ? item.second.mainInstance : item.second.main) === client && (port ? item.panel.mainInstance : item.panel.main) === client, "actual views share exact selected observation policy client");
      check(client.interval === expected[i].refreshInterval * (port ? 1000 : 1) && client.running, "actual selected typed schedule and untouched interval");
      if (port) {
        var count = expected[i][field] ? 2 : 3;
        check(client.portCount === count && item.panel.portCount === count, "selected count/filter over one unfiltered observation");
        check(!!find(item.panel, child => child.text === item.api.tr("panel.processInfo", {
                                                                       name: "system",
                                                                       pid: "90001"
                                                                     })) === !expected[i][field], "actual Panel child excludes only selected system port");
        check(find(item.bar, child => child.text === String(count)), "actual child Bar Text renders selected policy");
      } else {
        check(client.currentLocation === main.currentLocation && client.showCityName === expected[i][field], "selected display over one actual daemon observation");
        var city = find(item.bar, child => child.text === "Controlled City");
        check(city && city.visible === expected[i][field], "actual child Bar Text renders selected policy");
        check(find(item.panel, child => String(child.text).indexOf("Controlled City") >= 0), "actual selected Panel location Text");
      }
    }
    check(main._settingsConsumers.size === 4, "one client per context, not one per view");
    console.log("OBSERVATION_CONSUMERS " + JSON.stringify({
                                                            plugin: plugin,
                                                            scope: scope,
                                                            mode: mode,
                                                            boundary: name,
                                                            values: expected.map(value => value[field])
                                                          }));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_OBSERVATION_DISK"), Quickshell.env("PHA_OBSERVATION_CASE"), Quickshell.env("PHA_OBSERVATION_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === api.tr(port ? "settings.hideSystemPorts" : "settings.show-city") && item.toggled !== undefined);
    check(control, "actual page toggle");
    control.toggled(true);
    check(popup._pageApi.field(field).value === true, "actual toggle stages selected field");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== field)
        check(!popup._pageApi.field(key).pendingIntent, "untouched field has no intent: " + key);
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
        panel: create("panel", context)
      }));
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "page construction is nonpublishing");
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
      probe("edited", oldRed ? "old-red" : "finish");
    } else if (phase === "old-red") {
      var item = presentations[1];
      var consumer = port ? item.bar.portCount === 2 : (find(item.bar, child => child.text === "Controlled City")?.visible === true);
      check(consumer, "original shared observation does not render saved selected policy");
      throw new Error("original observation policy defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "native staged Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings[field] = true;
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
      probe("following", "actions");
    } else if (phase === "actions")
      actions();
    else if (phase === "retire") {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => (port ? item.bar.mainInstance : item.bar.main) === null), "selected context retirement releases every client");
      phase = "finish";
    } else if (phase === "finish")
      finish();
  }
  function actions() {
    var selectedView = presentations[1], inheritedView = presentations[3];
    var client = main.settingsConsumerFor(selected.settingsContext);
    actionRequests.reload();
    actionRequests.waitForJob();
    var rows = String(actionRequests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
    function count(command, args) {
      return rows.filter(row => row.command === command && JSON.stringify(row.argv) === JSON.stringify(args)).length;
    }
    function button(panel, key) {
      var item = find(panel, child => child.text === api.tr(key) && child.clicked !== undefined);
      check(item, "actual originating action button " + key);
      return item;
    }
    if (actionStep === 0) {
      actionStarted = Date.now();
      if (port) {
        check(typeof client.refresh === "function", "selected action client exposes every view command");
        button(selectedView.panel, "panel.refresh").clicked();
        var row = find(selectedView.panel, child => child.modelData?.port === 8080);
        var click = find(row, child => child.clicked !== undefined && child.hoverEnabled === true);
        check(click, "actual selected port row capture");
        click.clicked(null);
        check(selectedView.panel.pendingKillPid === "90002", "originating row captures exact PID");
        button(selectedView.panel, "panel.confirm").clicked();
        client.killPortElevated("9090", "UDP");
        client.killPortElevated("invalid", "TCP");
        client.killProcess("");
        actionStep = 4;
      } else {
        check(!client.relayClickConnects && main.settingsConsumerFor(inherited.settingsContext).relayClickConnects && client.clickAction === "toggle", "selected relay policy reaches actual action controls");
        button(selectedView.panel, "action.auto-select").clicked();
        actionStep = 1;
      }
    } else if (actionStep === 1 && count("mullvad", ["relay", "set", "location"]) === 1) {
      if (Date.now() - actionStarted < 250)
        return;
      check(count("mullvad", ["connect"]) === 0, "selected relay action does not borrow inherited connect policy");
      button(inheritedView.panel, "action.auto-select").clicked();
      actionStep = 2;
    } else if (actionStep === 2 && count("mullvad", ["connect"]) === 1) {
      button(selectedView.panel, "action.disconnect").clicked();
      var toggle = find(selectedView.panel, child => child.label === api.tr("toggles.lockdown") && child.toggled !== undefined);
      check(toggle, "actual selected lockdown toggle");
      toggle.toggled(true);
      actionStep = 3;
    } else if (actionStep === 3 && count("mullvad", ["disconnect"]) === 1 && count("mullvad", ["lockdown-mode", "set", "on"]) === 1)
      probe("actions", "retire");
    else if (actionStep === 4 && count("kill", ["90002"]) === 1 && rows.some(row => row.command === "ghostty"))
      probe("actions", "retire");
  }
  function finish() {
    console.log("OBSERVATION_NATIVE: " + (mode === "cold" ? "COLD_PASS " + plugin + " " + scope + " " + boundary : "PASS " + plugin + " " + scope + " " + mode));
    Qt.exit(0);
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
