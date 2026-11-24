// Native generic page publication joined to actual Main/Bar/Panel results.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_QUERY_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_QUERY_SCOPE")
  readonly property string mode: Quickshell.env("PHA_QUERY_MODE")
  readonly property string boundary: Quickshell.env("PHA_QUERY_BOUNDARY")
  readonly property bool latency: plugin === "latency-monitor"
  readonly property bool ssh: plugin === "ssh-sessions"
  readonly property bool oldRed: Quickshell.env("PHA_QUERY_OLD_RED") === "1"
  readonly property string field: latency ? "intervalSeconds" : ssh ? "terminalCommand" : "city"
  readonly property var editValue: latency ? 10 : ssh ? "terminal-selected" : "Selected"
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
  property int actionCount: 0
  property bool actionsDone: false
  FileView {
    id: requests
    path: Quickshell.env("PHA_QUERY_CASE") + "/requests.jsonl"
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
    path: Quickshell.env("PHA_QUERY_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: function (code) {
      if (code !== 0)
        root.fail("QUERY_DISK " + root.diskBoundary);
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
      throw new Error("QUERY_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
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
    requests.waitForJob();
    actionCount = requests.text().trim().split("\n").filter(line => line !== "").map(line => JSON.parse(line)).filter(row => row.command.indexOf("terminal-") === 0 || row.command === "ghostty").length;
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
    return presentations.every((item, index) => {
      if (item.api.pluginSettings[field] !== expected[index][field])
        return false;
      if (oldRed)
        return true;
      var client = main.settingsConsumerFor(item.api.settingsContext);
      if (ssh)
        return main.configLoaded && main.activeCount === 1 && client.terminalCommand === (expected[index].terminalCommand || main.detectedTerminal);
      if (latency)
        return client.hosts.length === 1 && client.hosts[0].lastRtt === expected[index].intervalSeconds;
      return !client.isLoading && client.prayerTimings && client.city === expected[index].city;
    });
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    var times = {
      Base: "23:11",
      Selected: "23:22",
      Sibling: "23:33",
      London: "23:44",
      Following: "23:55"
    };
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext);
      check(item.bar.mainInstance === client, "Bar has exact selected query client");
      check(item.second.mainInstance === client && item.panel.mainInstance === client, "all views of one API share one query client");
      if (i > 0)
        check(client !== presentations[0].bar.mainInstance, "distinct runtime contexts keep distinct query clients");
      var rendered;
      if (ssh) {
        check(client.interval === expected[i].pollInterval * 1000 && client.running, "selected polling retains native fractional seconds");
        check(client.activeCount === main.activeCount, "SSH observation owner remains singular");
        check(client.sortedHosts.length === (expected[i].showInactiveHosts ? 2 : 1), "selected host filter over shared observation");
        check(find(item.panel, child => child.text === "Active"), "actual child Panel host Text");
        check(!!find(item.panel, child => child.text === "Inactive") === expected[i].showInactiveHosts, "actual child Panel selected inactive-host projection");
        rendered = "1";
      } else if (latency) {
        var host = client.hosts[0], interval = expected[i].intervalSeconds;
        check(host._timer.running && host._timer.interval === interval * 1000, "actual selected Host Timer uses typed native interval");
        check(host.lastRtt === interval && host.samples.length > 0, "actual selected ping result reaches Host samples");
        rendered = "Controlled " + interval + "ms";
        check(find(item.panel, child => child.text === "Controlled"), "actual child Panel host Text");
        check(find(item.panel, child => child.text === interval + "ms"), "actual child Panel latency Text");
      } else {
        var time = times[expected[i].city];
        check(client.prayerTimings.Maghrib === time, "actual selected city query response");
        check(find(item.panel, child => child.text === item.panel.formatTime(time)), "actual child Panel prayer-time Text");
        rendered = client.iftarPassed ? item.api.tr("widget.suhoor") + " " + item.bar.suhoorTimeStr : item.bar.iftarTimeStr;
      }
      check(find(item.bar, child => child.text === rendered), "actual child Bar Text reflects selected query result");
    }
    check(main._settingsConsumers.size === 4, "one Main query client per API, never per view");
    console.log("QUERY_CONSUMERS " + JSON.stringify({
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
    disk.command = ["python3", "-B", Quickshell.env("PHA_QUERY_DISK"), Quickshell.env("PHA_QUERY_CASE"), Quickshell.env("PHA_QUERY_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual selected Settings opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, child => latency ? child.objectName === "settings-range-valueIntervalSeconds" : child.label === api.tr(ssh ? "settings.terminalOverride" : "settings.city.label") && child.editCommitted !== undefined);
    check(control, "actual query preference control");
    if (latency) {
      control.value = editValue;
      control.moved();
    } else {
      control.text = editValue;
      control.editCommitted(editValue);
    }
    check(popup._pageApi.field(field).value === editValue, "real control stages selected query intent");
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
      var initial = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(initial))
        return;
      observe(initial);
      if (mode === "cold") {
        if (ssh)
          phase = "actions";
        else
          finish();
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
      probe("edited", oldRed ? "old-red" : "finish");
    } else if (phase === "old-red") {
      if (latency && (!main.hosts.length || main.hosts[0].lastRtt < 0) || !latency && !main.prayerTimings)
        return;
      var item = presentations[1];
      var text = latency ? "Controlled 10ms" : main.iftarPassed ? item.api.tr("widget.suhoor") + " " + item.panel.formatTime("23:22") : item.panel.formatTime("23:22");
      check(find(item.bar, child => child.text === text), "original shared Main does not render the saved selected query");
      throw new Error("original shared Main defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field(field).reset(), "staged query Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings[field] = latency ? 18 : ssh ? "terminal-following" : "Following";
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
      probe("following", ssh ? "actions" : "retire");
    } else if (phase === "retire") {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => item.bar.mainInstance === null && item.second.mainInstance === null && item.panel.mainInstance === null), "retired contexts release every query client");
      phase = "finish";
    } else if (phase === "finish") {
      if (ssh && !actionsDone)
        phase = "actions";
      else
        finish();
    } else if (phase === "actions") {
      for (var item of presentations) {
        item.panel.selectedIndex = 0;
        item.panel.connectSelected();
      }
      phase = "action-results";
    } else if (phase === "action-results") {
      requests.reload();
      requests.waitForJob();
      var rows = requests.text().trim().split("\n").filter(line => line !== "").map(line => JSON.parse(line));
      if (rows.filter(row => row.command.indexOf("terminal-") === 0 || row.command === "ghostty").length < actionCount + 4)
        return;
      actionsDone = true;
      if (mode === "follow")
        phase = "retire";
      else
        finish();
    }
  }
  function finish() {
    console.log(mode === "cold" ? "QUERY_NATIVE: COLD_PASS " + plugin + " " + scope + " " + boundary : "QUERY_NATIVE: PASS " + plugin + " " + scope + " " + mode);
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
