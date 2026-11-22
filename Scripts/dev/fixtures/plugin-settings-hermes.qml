import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_HERMES_CASE")
  readonly property string scenario: Quickshell.env("PHA_HERMES_SCENARIO")
  readonly property var ports: JSON.parse(Quickshell.env("PHA_HERMES_PORTS"))
  readonly property bool localScenario: ["local", "failed-start"].includes(scenario)
  property var main: null
  property var panel: null
  property var bar: null
  property var launcher: null
  property var connectionBefore: null
  property bool callbackCalled: false
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  QtObject {
    id: shared
    property bool alive: true
    property var pluginSettings: ({
                                    clientOnlyMode: !root.localScenario,
                                    bridgeHost: root.localScenario ? "remote.invalid" : "127.0.0.1",
                                    bridgePort: root.localScenario ? root.ports[1] : root.ports[0],
                                    bridgeTokenManual: "shared-token",
                                    stateFile: root.base + "/local-state/state.json",
                                    hermesHome: root.base + "/hermes-home",
                                    hermesCommand: "inert-not-invoked",
                                    autoStartBridge: true,
                                    autoStartGateway: false,
                                    configured: true,
                                    statusPollIntervalSec: 3600,
                                    panelPinned: false,
                                    defaultModel: "",
                                    defaultProvider: ""
                                  })
    property var manifest: ({
                              metadata: {
                                defaultSettings: {
                                  bridgePort: root.localScenario ? root.ports[0] : 19777,
                                  statusPollIntervalSec: 30
                                }
                              }
                            })
    property string pluginDir: Quickshell.env("PHA_HERMES_PLUGIN")
    property var mainInstance: root.main
    property var panelOpenScreen: Quickshell.screens[0]
    readonly property var settingsContext: sharedContext
    function tr(key) {
      return key;
    }
    function saveSettings() {
      throw new Error("lifetime context must not publish");
    }
    function openPanel(screen, item) {
    }
    function closePanel(screen) {
    }
    function withCurrentScreen(callback) {
      callback(Quickshell.screens[0]);
    }
  }
  QtObject {
    id: selected
    property bool alive: true
    property var pluginSettings: Object.assign({}, shared.pluginSettings, {
                                                 defaultModel: "selected-model",
                                                 defaultProvider: "selected-provider",
                                                 launcherPrefix: ">selected",
                                                 showToolActivity: true
                                               })
    property var manifest: shared.manifest
    property string pluginDir: shared.pluginDir
    property var mainInstance: root.main
    property var panelOpenScreen: Quickshell.screens[0]
    readonly property var settingsContext: selectedContext
    function tr(key) {
      return key;
    }
    function saveSettings() {
      throw new Error("lifetime context must not publish");
    }
    function openPanel(screen, item) {
    }
    function closePanel(screen) {
    }
    function withCurrentScreen(callback) {
      callback(Quickshell.screens[0]);
    }
  }
  QtObject {
    id: sharedContext
    readonly property var settingsView: shared.pluginSettings
    function current() {
      return shared.alive;
    }
  }
  QtObject {
    id: selectedContext
    readonly property var settingsView: selected.pluginSettings
    function current() {
      return selected.alive;
    }
  }
  FileView {
    id: release
    path: root.base + "/release"
    printErrors: false
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    printErrors: false
  }
  FileView {
    id: localState
    path: root.base + "/local-state/state.json"
    printErrors: false
  }
  FileView {
    id: localToken
    path: root.base + "/local-state/bridge.token"
    printErrors: false
  }
  FileView {
    id: startFailure
    path: root.base + "/fail-start"
    printErrors: false
  }
  PanelWindow {
    visible: true
    implicitWidth: 1100
    implicitHeight: 900
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("HERMES_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function create(name, api, extra) {
    const component = Qt.createComponent("file://" + shared.pluginDir + "/" + name + ".qml");
    check(component.status === Component.Ready, component.errorString());
    const item = component.createObject(content, Object.assign({
                                                                 pluginApi: api
                                                               }, extra || {}));
    check(item, "actual " + name);
    return item;
  }
  function texts(item, value, seen) {
    if (!item)
      return false;
    seen = seen || new Set();
    if (seen.has(item))
      return false;
    seen.add(item);
    if (item.text === value)
      return true;
    for (const group of [item.data, item.children, item.contentData])
      if (group && typeof group.length === "number")
        for (let i = 0; i < group.length; i++)
          if (texts(group[i], value, seen))
            return true;
    return item.contentItem ? texts(item.contentItem, value, seen) : false;
  }
  function finish() {
    console.log("HERMES_OBSERVED " + JSON.stringify({
                                                      pendingRestart: main?.pendingRestart,
                                                      model: panel?.modelLabel,
                                                      callbackCalled: callbackCalled,
                                                      appliedPort: main?.bridgePort
                                                    }));
    main?.destroy();
    main = null;
    phase = "quiescent";
  }
  function heldEntered() {
    requests.reload();
    requests.waitForJob();
    return requests.loaded && requests.text().includes('"path": "/sessions"');
  }
  function drive() {
    check(Date.now() - since < 18000, "finite phase");
    if (phase === "begin") {
      main = create("Main", shared);
      phase = "online";
    } else if (phase === "online" && scenario === "failed-start" && main.state.bridge.error === "Bridge failed to start") {
      check(!main.connection.ready, "failed process not ready");
      startFailure.setText("");
      phase = "retry-start";
    } else if (phase === "retry-start" && Date.now() - since > 100) {
      main.ensureBridge();
      phase = "retry-online";
    } else if (phase === "retry-online" && main.connection?.ready && main.state.summary?.model?.name === "local-model") {
      finish();
    } else if (phase === "online" && main.connection?.ready && (scenario === "local" || main.state.session?.id === "chat-shared")) {
      connectionBefore = main.connection;
      panel = create("Panel", selected);
      bar = create("BarWidget", selected, {
                     screen: Quickshell.screens[0]
                   });
      launcher = create("LauncherProvider", selected);
      check(panel.settingsConsumer === bar.settingsConsumer && bar.settingsConsumer === launcher.settingsConsumer, "one selected client across renderers");
      check(panel.settingsConsumer !== main.settingsConsumer, "independent selected identity");
      check(main.pinnedPanelApi === null && main.connection === connectionBefore, "renderers do not select owner");
      if (scenario === "local") {
        check(!main.clientOnlyMode && main.bridgeHost === "127.0.0.1" && main.bridgePort === ports[0], "local mode ignores configured remote host/port");
        check(main.expandedStateFile === base + "/local-state/state.json" && main.hermesCommand === "inert-not-invoked", "literal local source inputs");
        check(main.bridgeToken.length > 0 && main.bridgeToken !== "shared-token", "actual local token reader");
        const value = JSON.parse(JSON.stringify(main.state));
        value.session.id = "local-file";
        value.messages = [
              {
                role: "assistant",
                text: "local-file-message"
              }
            ];
        localState.setText(JSON.stringify(value));
        localToken.setText("rotated-local-token");
        phase = "local-file";
      } else if (scenario === "owner-retire") {
        shared.alive = false;
        phase = "owner-retired";
      } else if (scenario === "model-retire") {
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  defaultModel: "older-model"
                                                });
        check(main.applySettings(selected.settingsContext), "held model desired input");
        phase = "model-held";
      } else if (scenario === "model") {
        check(main.applySettings(selected.settingsContext), "selected accepted policy");
        phase = "model";
      } else if (["pending", "held-source"].includes(scenario)) {
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  bridgePort: ports[1],
                                                  bridgeTokenManual: "selected-token"
                                                });
        check(main.applySettings(selected.settingsContext), "pending accepted policy");
        if (scenario === "held-source")
          main.listSessions(function () {
            root.callbackCalled = true;
          }, selected.settingsContext);
        phase = "pending";
      } else if (scenario.startsWith("held-")) {
        check(main.listSessions(function () {
          root.callbackCalled = true;
        }, selected.settingsContext), "held selected request");
        phase = "held";
      } else if (scenario === "timers") {
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  statusPollIntervalSec: 2.9
                                                });
        phase = "timer-int";
      } else {
        check(launcher.prefix === ">selected" && panel.showToolActivity, "selected consumers");
        check(main.openPinnedPanel(Quickshell.screens[0], selected), "originating pinned window");
        phase = "pinned";
      }
    } else if (phase === "owner-retired" && !main.connection) {
      check(main.state.bridge.status === "offline" && main.state.messages[0].text === "retained-shared", "owner loss withdraws online status without deleting chat");
      finish();
    } else if (phase === "model-held") {
      requests.reload();
      requests.waitForJob();
      if (!requests.text().includes('"model": "older-model"'))
        return;
      shared.pluginSettings = Object.assign({}, shared.pluginSettings, {
                                              defaultProvider: "latest-provider",
                                              defaultModel: "latest-model"
                                            });
      main.applySettings(shared.settingsContext);
      selected.alive = false;
      release.setText("release");
      phase = "model-latest";
    } else if (phase === "model-latest" && main.state.hermes?.model === "latest-model" && !main.activeModel) {
      check(!main.pendingModel, "latest accepted model reconciled after retired request settlement");
      finish();
    } else if (phase === "local-file" && main.bridgeToken === "rotated-local-token" && main.state.session?.id === "local-file") {
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                clientOnlyMode: true,
                                                bridgeHost: "127.0.0.1",
                                                bridgePort: ports[1],
                                                bridgeTokenManual: "selected-token"
                                              });
      main.applySettings(selected.settingsContext);
      phase = "local-pending";
    } else if (phase === "local-pending" && Date.now() - since > 200) {
      check(main.pendingRestart && main.connection === connectionBefore && main.state.messages[0].text === "local-file-message", "local readers retained through pending restart");
      check(main.createSession(selected.settingsContext), "local to remote explicit replacement");
      phase = "local-replaced";
    } else if (phase === "local-replaced" && main.state.session?.id === "chat-selected" && !main.pendingBoundary) {
      localState.setText(JSON.stringify({
                                          session: {
                                            id: "stale-file"
                                          },
                                          messages: []
                                        }));
      localToken.setText("stale-token");
      phase = "local-stale";
    } else if (phase === "local-stale" && Date.now() - since > 300) {
      check(main.bridgeToken === "selected-token" && main.state.session?.id === "chat-selected", "retired local readers cannot publish into remote source");
      finish();
    } else if (phase === "model" && main.state.hermes.model === "selected-model" && texts(panel, "fixture / selected-model")) {
      check(main.connection === connectionBefore, "model does not replace chat transport");
      finish();
    } else if (phase === "pending" && Date.now() - since > 300 && (scenario !== "held-source" || heldEntered())) {
      check(main.pendingRestart && main.connection === connectionBefore, "pending keeps applied generation");
      check(main.bridgePort === ports[0] && main.bridgeToken === "shared-token", "coherent old target and token");
      check(main.state.messages[0].text === "retained-shared" && !main.state.session.running, "prompt completion keeps chat");
      check(main.createSession(selected.settingsContext), "explicit boundary adopts requested origin");
      release.setText("release");
      phase = "replaced";
    } else if (phase === "replaced" && main.state.session?.id === "chat-selected" && !main.pendingBoundary) {
      check(main.bridgePort === ports[1] && main.bridgeToken === "selected-token" && !main.pendingRestart, "new session coherent target");
      check(!callbackCalled, "retired connection callback fenced");
      finish();
    } else if (phase === "held" && heldEntered()) {
      if (scenario === "held-destroy") {
        main.destroy();
        main = null;
      } else
        selected.alive = false;
      release.setText("release");
      phase = "held-released";
    } else if (phase === "held-released" && Date.now() - since > 500) {
      check(!callbackCalled, "retired request cannot call retained consumer");
      finish();
    } else if (phase === "timer-int" && panel.settingsConsumer.pollSeconds === 2) {
      check(panel.settingsConsumer.pollTimer.interval === 2000, "int seconds before scaling");
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                statusPollIntervalSec: 0
                                              });
      phase = "timer-zero";
    } else if (phase === "timer-zero" && panel.settingsConsumer.pollSeconds === 0) {
      check(panel.settingsConsumer.pollTimer.interval === 0 && panel.settingsConsumer.pollTimer.running, "original zero policy");
      selected.alive = false;
      finish();
    } else if (phase === "pinned" && Date.now() - since > 200) {
      check(main.pinnedPanelApi === selected, "pinned API retains originating runtime owner");
      const action = launcher.getResults(">selected ask")[0].onActivate;
      selected.alive = false;
      action();
      check(!main.pinnedPanelRequested, "retired pin current fence");
      finish();
    } else if (phase === "quiescent" && Date.now() - since > 400) {
      driver.stop();
      console.log("HERMES_CONTRACT: PASS " + scenario);
      Qt.exit(0);
    }
  }
  Timer {
    id: driver
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        stop();
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
}
