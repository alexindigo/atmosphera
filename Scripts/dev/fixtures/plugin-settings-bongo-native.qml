// Actual selected page/native owner and Bar children; inert IO/audio only.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Media
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_BONGO_SCOPE")
  readonly property string mode: Quickshell.env("PHA_BONGO_MODE")
  readonly property string boundary: Quickshell.env("PHA_BONGO_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_BONGO_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_BONGO_OLD_RED") === "1"
  property bool started: false
  property string phase: "startup"
  property double phaseStarted: Date.now()
  onPhaseChanged: phaseStarted = Date.now()
  property var api: null
  property var selected: null
  property var main: null
  property var presentations: []
  property var receipt: null
  property string afterDisk: ""
  property string diskBoundary: ""
  property var contextA: null
  property var contextB: null
  property var clientA: null
  property var clientB: null
  property var oldMonitor: null
  property int oldRequests: 0
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/slowbongo/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/slowbongo/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  FileView {
    id: requestsFile
    path: root.casePath + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: eventFile
    path: root.casePath + "/event-shared"
    printErrors: false
  }
  FileView {
    id: releaseFile
    path: root.casePath + "/check-release"
    printErrors: false
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete Bongo documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1100
    implicitHeight: 950
    Item {
      id: content
      width: 1100
      height: 950
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  Component {
    id: contextFactory
    QtObject {
      property bool valid: true
      property var settingsView: ({})
      function current() {
        return valid;
      }
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("BONGO_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
        var found = find(child, predicate);
        if (found)
          return found;
      }
    }
    return null;
  }
  function create(entry, context) {
    var component = Qt.createComponent("file://" + api.pluginDir + "/" + api.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var item = PluginLoader.createObject("slowbongo", entry, component, content, context, {
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
    Registry.installedPlugins = {
      "slowbongo": manifest
    };
    Service._openSettingsOwner("slowbongo", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("slowbongo", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "slowbongo": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor("slowbongo", {
                                                                       kind: "bar",
                                                                       list: "global",
                                                                       section: "left",
                                                                       index: index
                                                                     }));
        selected = contexts[0];
        presentations = [api].concat(contexts).map(context => ({
          api: context,
          bar: null,
          second: null
        }));
        phase = "runtime";
      } catch (error) {
        fail(error);
      }
    });
  }
  function values(name) {
    expectedFile.reload();
    expectedFile.waitForJob();
    var expected = JSON.parse(expectedFile.text())[name], defaults = api.manifest.metadata.defaultSettings;
    return [Object.assign({}, defaults, expected.shared)].concat(expected.bar.widgets.left.map(row => Object.assign({}, defaults, expected.shared, row.instanceSettings || {})));
  }
  function ready(name) {
    var expected = values(name);
    return presentations.every((item, index) => Object.keys(api.manifest.metadata.settingsSchema.fields).every(key => JSON.stringify(item.api.pluginSettings[key]) === JSON.stringify(expected[index][key])));
  }
  function cat(bar) {
    return find(bar, child => child.font !== undefined && child.font.weight === Font.Thin);
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext), child = cat(item.bar);
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client, "actual Bars share exact captured client");
      check(child && child.font.pixelSize === Math.round(item.bar.capsuleHeight * expected[i].catSize), "actual Bar child font uses selected size");
      check(item.bar.catOffsetY === expected[i].catOffsetY && item.bar.widthPadding === expected[i].widthPadding, "selected geometry and hidden width padding");
      check(child.color.toString() === item.bar.resolveColor(expected[i].catColor).toString(), "actual Bar child color uses selected color");
      check(client.idleTimeout === Math.round(expected[i].idleTimeout) && client.waitingTimeout === Math.round(expected[i].waitingTimeout), "original int Timer admission is selected");
      check(client.raveMode === expected[i].raveMode && client.tappyMode === expected[i].tappyMode && client.useMprisFilter === expected[i].useMprisFilter, "selected audio and MPRIS configuration");
      check(JSON.stringify(client.inputDevices) === JSON.stringify(expected[i].inputDevices), "selected source demand");
    }
    check(main._settingsConsumers.size === 4, "one client per API not renderer");
    check(SpectrumService.registerCalls === 1 && SpectrumService.registrations.size === 1, "one common Spectrum registration");
    console.log("BONGO_CONSUMERS " + JSON.stringify({
                                                      scope: scope,
                                                      mode: mode,
                                                      boundary: name,
                                                      clients: main._settingsConsumers.size
                                                    }));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_BONGO_DISK"), casePath, Quickshell.env("PHA_BONGO_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.objectName === "settings-range-editCatSize");
    check(control, "actual cat size control");
    control.moved(1.25);
    check(popup._pageApi.field("catSize").value === 1.25, "slider stages intent");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== "catSize")
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
  function editPolicy() {
    var color = find(popup.settingsPage, item => item.currentKey !== undefined && item.selected !== undefined);
    check(color, "actual color choice");
    color.selected("tertiary");
    var offset = find(popup.settingsPage, item => item.objectName === "settings-range-editCatOffsetY");
    check(offset, "actual offset slider");
    offset.moved(0.2);
    for (var label of ["rave-mode", "tappy-mode", "mpris-filter"]) {
      var toggle = find(popup.settingsPage, item => item.label === api.tr("settings." + label) && item.toggled !== undefined);
      check(toggle, "actual mode toggle " + label);
      toggle.toggled(true);
    }
    popup.settingsPage.toggleDevice("/dev/input/event90");
  }
  function requests() {
    requestsFile.reload();
    requestsFile.waitForJob();
    return requestsFile.text().trim().split("\n").filter(line => line.length).map(line => JSON.parse(line));
  }
  function count(command, device) {
    return requests().filter(row => row.command === command && row.argv.indexOf(device) >= 0).length;
  }
  function life() {
    if (phase === "life-start") {
      contextA = contextFactory.createObject(root, {
                                               settingsView: {
                                                 inputDevices: ["/fixture/shared"],
                                                 idleTimeout: 70.4,
                                                 waitingTimeout: 240.4,
                                                 tappyMode: true,
                                                 raveMode: true,
                                                 useMprisFilter: true
                                               }
                                             });
      contextB = contextFactory.createObject(root, {
                                               settingsView: {
                                                 inputDevices: ["/fixture/shared"],
                                                 idleTimeout: 300.4,
                                                 waitingTimeout: 600.4,
                                                 tappyMode: true,
                                                 raveMode: true
                                               }
                                             });
      clientA = main.settingsConsumerFor(contextA);
      clientB = main.settingsConsumerFor(contextB);
      check(main.settingsConsumerFor(contextA) === clientA && main._deviceMonitors.size === 1, "same context and source share owners");
      phase = "life-source";
    } else if (phase === "life-source" && count("evtest", "/fixture/shared") === 1) {
      oldMonitor = main._deviceMonitors.get("/fixture/shared");
      contextB.settingsView = Object.assign({}, contextB.settingsView, {
                                              inputDevices: ["/fixture/other"]
                                            });
      check(main._deviceMonitors.get("/fixture/shared") === oldMonitor, "unchanged source owner survives another lease replacement");
      eventFile.setText("Event EV_KEY KEY_SPACE value 1\n");
      phase = "life-press";
    } else if (phase === "life-press" && clientA.catState === 3) {
      check(clientB.catState === 0, "only selected source receives actual input");
      eventFile.setText("Event EV_KEY KEY_SPACE value 0\n");
      phase = "life-release";
    } else if (phase === "life-release" && clientA.catState === 0) {
      SpectrumService.isIdle = false;
      MediaService.isPlaying = false;
      SpectrumService.values = Array(16).fill(1);
      check(!clientA.useTappyMode && clientA.catState === 0 && clientB.catState === 3 && clientB.showRainbowColor, "audio beat and MPRIS filtering use selected policy");
      phase = "life-idle";
    } else if (phase === "life-idle" && Date.now() - phaseStarted > 380) {
      check(clientB.catState === 0 && !clientB.isFlashing, "actual idle and flash timers settle");
      MediaService.isPlaying = true;
      SpectrumService.values = Array(16).fill(0);
      SpectrumService.values = Array(16).fill(1);
      check(clientA.useTappyMode && clientA.catState !== 0, "MPRIS change admits selected animation");
      main.paused = true;
      check(clientA.catState === 0 && clientB.catState === 0 && cat(presentations[1].bar).text === "ef", "common pause resets all clients and actual Bar glyph");
      main.paused = false;
      phase = "life-wait";
    } else if (phase === "life-wait" && Date.now() - phaseStarted > 350) {
      check(clientA.waiting && !clientB.waiting, "actual waiting timers use independently selected intervals");
      contextA.valid = false;
      phase = "life-replaced";
    } else if (phase === "life-replaced" && !main._deviceMonitors.has("/fixture/shared")) {
      check(main._deviceMonitors.size === 1, "last source lease retires only that observer");
      contextB.settingsView = Object.assign({}, contextB.settingsView, {
                                              inputDevices: ["/fixture/retry-held-check"]
                                            });
      phase = "life-retry";
    } else if (phase === "life-retry") {
      var monitor = main._deviceMonitors.get("/fixture/retry-held-check");
      var timer = find(monitor, item => item.interval === 30000 && item.running === true && item.restart !== undefined);
      if (!timer)
        return;
      check(monitor.retryCount === 1 && monitor.hasNotified, "failed observer retains original retry and notice admission");
      timer.interval = 40;
      timer.restart();
      phase = "life-check";
    } else if (phase === "life-check" && count("test", "/fixture/retry-held-check") === 1) {
      contextB.valid = false;
      oldRequests = requests().length;
      releaseFile.setText("release\n");
      phase = "life-retired";
    } else if (phase === "life-retired" && Date.now() - phaseStarted > 220) {
      check(main._deviceMonitors.size === 0 && main._settingsConsumers.size === 4 && requests().length === oldRequests, "retired held check cannot restart or notify");
      Service.loadedPlugins = ({});
      phase = "all-retired";
    }
  }
  function drive() {
    check(Date.now() - phaseStarted < 22000, "finite operation deadline");
    if (phase.startsWith("life-")) {
      life();
      return;
    }
    if (phase === "runtime" && presentations.every(item => item.api.settingsReady)) {
      for (var item of presentations) {
        item.bar = create("barWidget", item.api);
        item.second = create("barWidget", item.api);
      }
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" || mode === "life" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : mode === "policy" ? "following" : boundary;
      if (!ready(name))
        return;
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "life")
        phase = "life-start";
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open(mode === "policy" ? "policy-page" : "reset-page");
    } else if (phase === "open-discard")
      open("discard-page");
    else if (phase === "discard-page" && popup.opened && popup.settingsPage) {
      check(!popup.dirty && !popup._editor.dirty, "construction has no intent");
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
      check(cat(presentations[1].bar).font.pixelSize === Math.round(presentations[1].bar.capsuleHeight * 1.25), "original Bar child uses saved selected size");
      throw new Error("Bongo defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("catSize").reset(), "staged native Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.catSize = 1.25;
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
      probe("following", "finish");
    } else if (phase === "policy-page" && popup.opened && popup.settingsPage) {
      editPolicy();
      apply("policy-applied");
    } else if (phase === "policy-applied" && accepted() && ready("policy")) {
      observe("policy");
      probe("policy", "finish");
    } else if (phase === "all-retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 0 && main._deviceMonitors.size === 0, "all selected clients retire");
      main.destroy();
      phase = "spectrum-retired";
    } else if (phase === "spectrum-retired") {
      check(SpectrumService.unregisterCalls === 1 && SpectrumService.registrations.size === 0, "common Spectrum owner unregisters once");
      finish();
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("BONGO_NATIVE: PASS " + scope + " " + mode + " " + boundary);
    Qt.exit(0);
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Timer {
    interval: 50
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
