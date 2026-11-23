// Actual scoped page, native documents and final Bar/Panel consumers.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Plugins
import qs.Widgets

ShellRoot {
  id: root
  readonly property string scope: Quickshell.env("PHA_HERMES_SCOPE")
  readonly property string mode: Quickshell.env("PHA_HERMES_MODE")
  readonly property string boundary: Quickshell.env("PHA_HERMES_BOUNDARY")
  readonly property string casePath: Quickshell.env("PHA_HERMES_CASE")
  readonly property bool oldRed: Quickshell.env("PHA_HERMES_OLD_RED") === "1"
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
  property var autoContext: null
  property var autoSession: null
  property var oldSession: null
  property int requestCount: 0
  FileView {
    id: requestsFile
    path: root.casePath + "/requests.jsonl"
    blockLoading: true
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
  FileView {
    id: manifestFile
    path: Settings.configDir + "plugins/hermes-ssh-chat/manifest.json"
    blockLoading: true
  }
  FileView {
    id: dictionaryFile
    path: Settings.configDir + "plugins/hermes-ssh-chat/i18n/en.json"
    blockLoading: true
  }
  FileView {
    id: expectedFile
    path: root.casePath + "/expectations.json"
    blockLoading: true
  }
  Process {
    id: disk
    onExited: code => {
      if (code !== 0)
        root.fail("independent complete Hermes documents: " + root.diskBoundary);
      else
        root.phase = root.afterDisk;
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1200
    implicitHeight: 950
    Item {
      id: content
      width: 1200
      height: 950
    }
    NPluginSettingsPopup {
      id: popup
      screen: Quickshell.screens[0]
      onSettingsCompleted: result => root.receipt = result
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("HERMES_ASSERT: " + scope + "/" + mode + "/" + phase + ": " + message);
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
    var item = PluginLoader.createObject("hermes-ssh-chat", entry, component, content, context, {
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
      "hermes-ssh-chat": manifest
    };
    Service._openSettingsOwner("hermes-ssh-chat", function (owner) {
      try {
        check(owner !== null, "actual native owner");
        api = Service.createPluginAPI("hermes-ssh-chat", manifest, owner, dictionary, dictionary, {});
        Service.loadedPlugins = {
          "hermes-ssh-chat": {
            api: api
          }
        };
        main = create("main", api);
        api.mainInstance = main;
        var contexts = [0, 1, 2].map(index => PluginInstances.apiFor("hermes-ssh-chat", {
                                                                       kind: "bar",
                                                                       list: "global",
                                                                       section: "left",
                                                                       index: index
                                                                     }));
        selected = contexts[0];
        presentations = [api].concat(contexts).map(context => ({
          api: context,
          bar: null,
          second: null,
          panel: null
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
  function barText(bar) {
    return find(bar, child => child.text === api.tr("widget.label") && child.pointSize !== undefined);
  }
  function observe(name) {
    if (oldRed)
      return;
    var expected = values(name);
    for (var i = 0; i < presentations.length; i++) {
      var item = presentations[i], client = main.settingsConsumerFor(item.api.settingsContext), child = barText(item.bar);
      check(item.bar.settingsConsumer === client && item.second.settingsConsumer === client && item.panel.settingsConsumer === client, "actual views share exact captured session");
      check(child && child.visible === (expected[i].showBarText && !item.bar.isVertical), "actual Bar text visibility uses selected policy");
      check(item.panel.contentPreferredWidth === Math.round(Math.max(720, Math.min(1800, expected[i].panelWidth)) * Style.uiScaleRatio), "selected Panel width");
      check(item.panel.terminalRows === expected[i].terminalRows && item.panel.terminalCols === expected[i].terminalCols && item.panel.terminalFontSize === expected[i].terminalFontSize, "selected terminal presentation");
    }
    check(main._settingsConsumers.size === 4, "one session per API, not view");
    console.log("HERMES_CONSUMERS " + JSON.stringify({
                                                       scope: scope,
                                                       mode: mode,
                                                       boundary: name,
                                                       sessions: main._settingsConsumers.size
                                                     }));
  }
  function probe(name, next) {
    afterDisk = next;
    diskBoundary = name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_HERMES_DISK"), casePath, Quickshell.env("PHA_HERMES_OUTPUT") + "/persisted", name];
    disk.running = true;
  }
  function probeChildren(name, live, next) {
    afterDisk = next;
    diskBoundary = "children-" + name;
    phase = "disk";
    disk.command = ["python3", "-B", Quickshell.env("PHA_HERMES_CHILDREN"), casePath, Quickshell.env("PHA_HERMES_OUTPUT") + "/children-" + name + ".json", name, JSON.stringify(live)];
    disk.running = true;
  }
  function open(next) {
    check(scope === "shared" ? popup.openPluginSettings(api.manifest, "settings") : popup.openInstanceSettings(api.manifest, selected, "settings"), "actual scoped page opens");
    phase = next;
  }
  function edit() {
    var control = find(popup.settingsPage, item => item.label === api.tr("settings.showBarText.label") && item.toggled !== undefined);
    check(control, "actual text toggle");
    control.toggled(false);
    check(popup._pageApi.field("showBarText").value === false, "toggle stages intent");
    for (var key of Object.keys(api.manifest.metadata.settingsSchema.fields))
      if (key !== "showBarText")
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
  function requests() {
    requestsFile.reload();
    requestsFile.waitForJob();
    return requestsFile.text().trim().split("\n").filter(line => line.length).map(line => JSON.parse(line));
  }
  function starts(target) {
    return requests().filter(row => row.event === "start" && row.target === target);
  }
  function terminal(panel) {
    return find(panel, item => item.rawText !== undefined && item.focusTerminal !== undefined);
  }
  function terminalText(panel) {
    return find(terminal(panel), item => item.readOnly === true && item.textFormat !== undefined);
  }
  function connectPanel(index, host, port, user, password) {
    var panel = presentations[index].panel;
    panel.valueHost = host;
    panel.valuePort = port;
    panel.valueUser = user;
    panel.valuePassword = password;
    panel.doConnect();
    check(panel.valuePassword === "", "Panel clears transient password");
  }
  function automatic(values) {
    var context = contextFactory.createObject(root, {
                                                settingsView: Object.assign({
                                                                              host: "auto.invalid",
                                                                              user: "auto-user",
                                                                              port: 2223,
                                                                              terminalRows: 23,
                                                                              terminalCols: 93,
                                                                              autoConnectOnStartup: true,
                                                                              rememberLastTarget: false
                                                                            }, values || {})
                                              });
    var origin = {
      settingsContext: context,
      pluginSettings: context.settingsView,
      tr: api.tr,
      saveSettings: function () {
        throw new Error("unexpected automatic writer");
      }
    };
    var session = main.settingsConsumerFor(context);
    session.activate(origin);
    session.activate(origin);
    return {
      context: context,
      session: session,
      origin: origin
    };
  }
  function life() {
    var first = presentations[1], second = presentations[2];
    if (phase === "life-connect") {
      check(requests().length === 0, "Main and non-auto views do not connect");
      connectPanel(1, "first.invalid", 2201, "first-user", "synthetic-password");
      connectPanel(2, "second.invalid", 2202, "second-user", "");
      phase = "life-connected";
    } else if (phase === "life-connected" && first.panel.settingsConsumer.connected && second.panel.settingsConsumer.connected && !selected._pendingSettingsSaves && !second.api._pendingSettingsSaves) {
      check(first.panel.settingsConsumer !== second.panel.settingsConsumer, "different contexts retain different sessions");
      for (var item of [first, second]) {
        var target = item === first ? "first-user@first.invalid" : "second-user@second.invalid";
        check(starts(target).length === 1, "one real SSH child per selected connection");
        check(item.panel.settingsConsumer.terminalBuffer.indexOf("REMOTE_" + target) >= 0, "real helper selected PTY output");
        check(terminalText(item.panel)?.text.indexOf("REMOTE_" + target) >= 0, "actual terminal child renders selected remote output");
      }
      check(starts("first-user@first.invalid")[0].rows === 32 && starts("first-user@first.invalid")[0].cols === 180, "selected initial PTY geometry");
      var before = first.panel.settingsConsumer.terminalBuffer;
      first.panel.settingsConsumer.handleMessage({}, JSON.stringify({
                                                                      type: "output",
                                                                      text: "STALE_OUTPUT"
                                                                    }));
      check(first.panel.settingsConsumer.terminalBuffer === before, "retired connection callback is fenced");
      terminal(first.panel).input("typed-first");
      phase = "life-input";
    } else if (phase === "life-input" && requests().some(row => row.event === "input" && row.target === "first-user@first.invalid" && row.text === "typed-first")) {
      check(first.panel.settingsConsumer.terminalBuffer.indexOf("INPUT_first-user@first.invalid:typed-first") >= 0, "terminal input reaches real helper PTY and returns");
      check(second.panel.settingsConsumer.terminalBuffer.indexOf("typed-first") < 0, "terminal input stays in originating session");
      oldSession = first.panel.settingsConsumer;
      first.panel.destroy();
      first.panel = null;
      phase = "life-reopen";
    } else if (phase === "life-reopen") {
      first.panel = create("panel", first.api);
      check(first.panel.settingsConsumer === oldSession && starts("first-user@first.invalid").length === 1, "same-context Panel reopen retains connection");
      check(terminalText(first.panel)?.text.indexOf("REMOTE_first-user@first.invalid") >= 0, "reopened terminal replays retained buffer");
      probe("remembered", "life-panel-source");
    } else if (phase === "life-panel-source") {
      first.panel.pluginApi = second.api;
      phase = "life-panel-second";
    } else if (phase === "life-panel-second" && Date.now() - phaseStarted > 40) {
      check(terminalText(first.panel)?.text.indexOf("REMOTE_second-user@second.invalid") >= 0 && terminalText(first.panel).text.indexOf("REMOTE_first-user@first.invalid") < 0, "reselected terminal renders only new session buffer");
      first.panel.pluginApi = first.api;
      phase = "life-panel-first";
    } else if (phase === "life-panel-first" && Date.now() - phaseStarted > 40) {
      check(terminalText(first.panel)?.text.indexOf("REMOTE_first-user@first.invalid") >= 0 && terminalText(first.panel).text.indexOf("REMOTE_second-user@second.invalid") < 0, "restored terminal replays only originating session buffer");
      phase = "life-replace";
    } else if (phase === "life-replace") {
      // No page receipt/effect is involved. Runtime action reads its originating API.
      connectPanel(1, "replacement.invalid", 2203, "replacement-user", "");
      phase = "life-replaced";
    } else if (phase === "life-replaced" && starts("replacement-user@replacement.invalid").length === 1 && first.panel.settingsConsumer.connected && !selected._pendingSettingsSaves) {
      check(first.panel.settingsConsumer.terminalBuffer.indexOf("REMOTE_first-user@first.invalid") < 0, "replacement starts a new terminal generation");
      check(second.panel.settingsConsumer.connected && starts("second-user@second.invalid").length === 1, "replacement cannot stop sibling connection");
      probe("replaced", "life-replacement-children");
    } else if (phase === "life-replacement-children") {
      if (!requests().some(row => row.event === "term" && row.target === "first-user@first.invalid"))
        return;
      probeChildren("replacement", ["replacement-user@replacement.invalid", "second-user@second.invalid"], "life-auto-start");
    } else if (phase === "life-auto-start") {
      var attempt = automatic();
      autoContext = attempt.context;
      autoSession = attempt.session;
      phase = "life-auto";
    } else if (phase === "life-auto" && starts("auto-user@auto.invalid").length === 1 && autoSession.connected) {
      check(starts("auto-user@auto.invalid")[0].rows === 23 && starts("auto-user@auto.invalid")[0].cols === 93, "automatic attempt captures selected dimensions");
      autoContext.settingsView = Object.assign({}, autoContext.settingsView, {
                                                 host: "later.invalid"
                                               });
      check(autoSession.host === "auto.invalid" && autoSession.connected, "active connection retains admitted source");
      autoContext.valid = false;
      var changed = automatic({
                                host: "queued.invalid"
                              });
      changed.context.settingsView = Object.assign({}, changed.context.settingsView, {
                                                     host: "changed.invalid"
                                                   });
      check(changed.session.autoSource.indexOf("changed.invalid") >= 0, "queued source changed before callback");
      var retired = automatic({
                                host: "retired.invalid"
                              });
      retired.context.valid = false;
      var manual = automatic({
                               host: "deferred.invalid"
                             });
      manual.session.connect(manual.origin, "manual.invalid", 2224, "manual-user", "", 24, 94);
      phase = "life-queued";
    } else if (phase === "life-queued" && starts("manual-user@manual.invalid").length === 1 && Date.now() - phaseStarted > 200) {
      check(starts("auto-user@queued.invalid").length === 0 && starts("auto-user@changed.invalid").length === 0, "queued auto source replacement is fenced");
      check(starts("auto-user@retired.invalid").length === 0 && starts("auto-user@deferred.invalid").length === 0, "queued owner loss and manual replacement are fenced");
      check(first.panel.settingsConsumer.connect(second.api, "foreign.invalid", 22, "foreign", "", 32, 80) === false, "foreign runtime writer is refused");
      probeChildren("auto-retired", ["replacement-user@replacement.invalid", "second-user@second.invalid", "manual-user@manual.invalid"], "life-retire-native");
    } else if (phase === "life-retire-native") {
      Service.loadedPlugins = ({});
      phase = "life-native-retired";
    } else if (phase === "life-native-retired" && !selected.settingsContext.current()) {
      check(main._settingsConsumers.size === 2, "native context retirement releases all four sessions");
      if (!["replacement-user@replacement.invalid", "second-user@second.invalid"].every(target => requests().some(row => row.event === "term" && row.target === target)))
        return;
      probeChildren("native-retired", ["manual-user@manual.invalid"], "life-destroy-main");
    } else if (phase === "life-destroy-main") {
      main.destroy();
      main = null;
      phase = "life-destroyed";
    } else if (phase === "life-destroyed" && Date.now() - phaseStarted > 200)
      probeChildren("main-destroyed", [], "life-final-documents");
    else if (phase === "life-final-documents")
      probe("retired", "finish");
  }
  function drive() {
    check(Date.now() - phaseStarted < 18000, "finite operation deadline");
    if (phase.startsWith("life-")) {
      life();
      return;
    }
    if (phase === "runtime" && presentations.every(item => item.api.settingsReady)) {
      for (var item of presentations) {
        item.bar = create("barWidget", item.api);
        item.second = create("barWidget", item.api);
        item.panel = create("panel", item.api);
      }
      phase = "initial";
    } else if (phase === "initial") {
      var name = mode === "edit" || mode === "life" ? "initial" : mode === "reset" ? "edited" : mode === "follow" ? "reset" : boundary;
      if (!ready(name))
        return;
      observe(name);
      if (mode === "cold")
        finish();
      else if (mode === "life")
        phase = "life-connect";
      else if (mode === "edit")
        probe("initial", "open-discard");
      else if (mode === "follow")
        phase = "change-base";
      else
        open("reset-page");
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
      check(barText(presentations[1].bar)?.visible === false, "original Bar child uses saved selected text policy");
      throw new Error("Hermes defect did not reproduce");
    } else if (phase === "reset-page" && popup.opened && popup.settingsPage && !popup.busy) {
      check(popup._pageApi.field("showBarText").reset(), "staged native Reset");
      observe("edited");
      probe("reset-staged", "reset-apply");
    } else if (phase === "reset-apply")
      apply("reset-applied");
    else if (phase === "reset-applied" && accepted() && ready("reset")) {
      observe("reset");
      probe("reset", "finish");
    } else if (phase === "change-base") {
      api.pluginSettings.showBarText = false;
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
    } else if (phase === "finish")
      finish();
  }
  function finish() {
    console.log("HERMES_NATIVE: PASS " + scope + " " + mode + " " + boundary);
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
