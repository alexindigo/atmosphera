// Actual Settings/native publication joined to retained-state projections.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_PROJECTION_PLUGIN")
  readonly property string scope: Quickshell.env("PHA_PROJECTION_SCOPE")
  readonly property string mode: Quickshell.env("PHA_PROJECTION_MODE")
  readonly property string boundary: Quickshell.env("PHA_PROJECTION_BOUNDARY")
  readonly property bool privacy: plugin === "privacy-indicator"
  readonly property bool kde: plugin === "kde-connect"
  readonly property bool oldRed: Quickshell.env("PHA_PROJECTION_OLD_RED") === "1"
  readonly property string field: privacy ? "micFilterRegex" : kde ? "hideIfNoDeviceConnected" : "precision"
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
    path: Quickshell.env("PHA_PROJECTION_CASE") + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete projection readback: " + root.diskBoundary);
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
      throw new Error("PROJECTION_NATIVE_ASSERT: " + plugin + "/" + scope + "/" + mode + "/" + phase + ": " + message);
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
    return presentations.every((item, index) => item.api.pluginSettings[field] === expected[index][field] && (!kde || item.api.pluginSettings.mainDeviceId === expected[index].mainDeviceId)) && (!kde || !!find(presentations[0].panel, child => child.text === "Phone A"));
  }
  function sample() {
    if (!privacy)
      return;
    var node = {
      isStream: true,
      audio: true,
      isSink: false,
      properties: {
        "media.class": "Stream/Input/Audio",
        "application.name": "Controlled Microphone"
      }
    };
    main.updateMicrophoneState([node], [
                                 {
                                   source: node
                                 }
                               ]);
  }
  function observe(name) {
    if (oldRed)
      return;
    sample();
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext);
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "actual views share exact selected projection client");
      if (privacy) {
        var active = expected[i][field] === "";
        check(client.micActive === active && item.bar.micActive === active, "selected microphone projection");
        check(find(item.bar, child => child.icon === (active ? "microphone" : "microphone-off")), "actual child Bar renders selected projection");
        check((item.bar.buildTooltip().indexOf("Controlled Microphone") >= 0) === active, "actual selected tooltip");
        check(JSON.stringify(client.accessHistory) === JSON.stringify(main.accessHistory), "one shared history owner, no projected history copy");
      } else if (kde) {
        var phoneB = expected[i].mainDeviceId === "phone-b";
        var battery = phoneB ? "42%" : "81%";
        check(find(item.bar, child => child.text === battery), "actual child Bar renders selected projection");
        check(find(item.panel, child => child.text === (phoneB ? "Phone B" : "Phone A")), "actual Panel renders selected device");
        check(item.bar.hideIfNoDeviceConnected === (expected[i][field] ?? false), "selected hide toggle consumer: " + JSON.stringify({
                                                                                                                                       index: i,
                                                                                                                                       api: item.api.pluginSettings[field],
                                                                                                                                       cfg: client.cfg.hideIfNoDeviceConnected,
                                                                                                                                       client: client.hideIfNoDeviceConnected,
                                                                                                                                       bar: item.bar.hideIfNoDeviceConnected,
                                                                                                                                       expected: expected[i][field] ?? false
                                                                                                                                     }));
      } else {
        client.clearAll();
        for (var action of ["1", "divide", "3", "equals"])
          client.pressButton(action);
        var answer = Number((1 / 3).toFixed(expected[i][field] ?? 8)).toString();
        check(main.currentInput === answer && item.panel.mainInst.displayText === answer, "originating precision reaches shared calculation");
        check(find(item.panel, child => child.text === answer), "actual Panel result child");
        check(find(item.bar, child => child.text === client.badgeText), "actual child Bar renders selected projection");
        check(client.currentInput === main.currentInput, "one calculation state, not per-context tokens/input");
      }
    }
    check(main._settingsConsumers.size === 4, "one projection per context, not per view");
    console.log("PROJECTION_CONSUMERS " + JSON.stringify({
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
    disk.command = ["python3", "-B", Quickshell.env(name === "actions" ? "PHA_PROJECTION_WAIT_DISK" : "PHA_PROJECTION_DISK"), Quickshell.env("PHA_PROJECTION_CASE"), Quickshell.env("PHA_PROJECTION_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped Settings opens");
    phase = next;
  }
  function edit() {
    var control;
    if (privacy) {
      control = find(popup.settingsPage, item => item.label === api.tr("settings.micFilterRegex.label") && item.editCommitted !== undefined);
      check(control, "actual microphone filter input");
      control.text = "Controlled";
      control.editCommitted();
    } else if (kde) {
      control = find(popup.settingsPage, item => item.label === api.tr("settings.no-device-connected-hide.label") && item.toggled !== undefined);
      check(control, "actual device hide toggle");
      control.toggled(true);
    } else {
      control = find(popup.settingsPage, item => item.objectName === "settings-range-valuePrecision");
      check(control, "actual precision slider");
      control.value = 2;
      control.moved();
    }
    check(popup._pageApi.field(field).value === (privacy ? "Controlled" : kde ? true : 2), "actual control stages selected field");
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
      var name = mode === "edit" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "actions" ? "following" : boundary;
      if (!ready(name))
        return;
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else if (mode === "actions")
        phase = "device-action";
      else
        open("reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "page construction nonpublishing");
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
      sample();
      var item = presentations[1];
      if (privacy)
        check(item.bar.micActive === false, "original shared projection does not render saved selected policy");
      else if (kde)
        check(item.bar.hideIfNoDeviceConnected === true, "original shared projection does not render saved selected policy");
      else {
        main.clearAll();
        for (var action of ["1", "divide", "3", "equals"])
          item.panel.mainInst.pressButton(action);
        check(find(item.panel, child => child.text === "0.33"), "original shared projection does not render saved selected policy");
      }
      throw new Error("original projection defect did not reproduce");
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
      api.pluginSettings[field] = privacy ? "Controlled" : kde ? true : 2;
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
    } else if (phase === "device-action") {
      var panel = presentations[1].panel;
      panel.deviceSwitcherOpen = true;
      var button = find(panel, item => item.text === "Phone A" && item.clicked !== undefined);
      if (!button)
        return;
      button.clicked();
      probe("actions", "device-saved");
    } else if (phase === "device-saved" && ready("actions")) {
      observe("actions");
      phase = "retire";
    } else if (phase === "retire") {
      Service.loadedPlugins = ({});
      phase = "retired";
    } else if (phase === "retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && presentations.every(item => item.bar.settingsConsumer === null), "retirement releases every context projection");
      phase = "finish";
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("PROJECTION_NATIVE: " + (mode === "cold" ? "COLD_PASS " + plugin + " " + scope + " " + boundary : "PASS " + plugin + " " + scope + " " + mode));
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
