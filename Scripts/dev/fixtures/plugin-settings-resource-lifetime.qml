import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_RESOURCE_CASE")
  readonly property string test: Quickshell.env("PHA_RESOURCE_TEST")
  readonly property bool clamshell: test.indexOf("clamshell-") === 0
  property var main: null
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  property var messages: []
  property var toasts: []
  QtObject {
    id: shared
    property var pluginSettings: root.clamshell ? ({
                                                     enabled: false,
                                                     internalConnectorRegex: "^eDP",
                                                     inhibitorWho: "shared-who",
                                                     notify: false
                                                   }) : ({
                                                           bindAddress: "127.0.0.1",
                                                           port: root.ports()[0],
                                                           token: "synthetic-shared",
                                                           pollIntervalSec: 1
                                                         })
    property var settingsContext: sharedContext
    property var manifest: ({
                              metadata: {
                                defaultSettings: {}
                              }
                            })
    property string pluginDir: Settings.configDir + "plugins/" + (root.clamshell ? "clamshell" : "agent-session-status")
    function tr(key, values) {
      return key;
    }
    function saveSettings() {
      pluginSettings = Object.assign({}, pluginSettings);
      root.messages.push("shared-save");
    }
  }
  QtObject {
    id: selected
    property var pluginSettings: root.clamshell ? ({
                                                     enabled: true,
                                                     internalConnectorRegex: "^eDP",
                                                     inhibitorWho: "selected-who",
                                                     notify: true
                                                   }) : ({
                                                           bindAddress: "127.0.0.1",
                                                           port: root.ports()[1],
                                                           token: "synthetic-selected",
                                                           pollIntervalSec: 1.9
                                                         })
    property var settingsContext: selectedContext
    function saveSettings() {
      pluginSettings = Object.assign({}, pluginSettings);
      root.messages.push("selected-save");
    }
  }
  QtObject {
    id: sharedContext
    property var settingsView: shared.pluginSettings
    property bool live: true
    function current() {
      return live;
    }
  }
  QtObject {
    id: selectedContext
    property var settingsView: selected.pluginSettings
    property bool live: true
    function current() {
      return live;
    }
  }
  FileView {
    id: input
    path: root.base + "/input.json"
    blockLoading: true
  }
  FileView {
    id: requestLog
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  FileView {
    id: barrier
    path: root.base + "/hold-exit"
    printErrors: false
  }
  FileView {
    id: release
    path: root.base + "/release-exit"
    printErrors: false
  }
  FileView {
    id: httpBarrier
    path: root.base + "/hold-" + root.ports()[1]
    printErrors: false
  }
  FileView {
    id: httpRelease
    path: root.base + "/release-" + root.ports()[1]
    printErrors: false
  }
  FileView {
    id: httpFailure
    path: root.base + "/fail-" + root.ports()[1]
    printErrors: false
  }
  property bool started: false
  function ports() {
    input.waitForJob();
    return JSON.parse(input.text()).ports;
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("RESOURCE_LIFETIME_ASSERT: " + test + "/" + phase + ": " + message);
  }
  function rows() {
    requestLog.reload();
    requestLog.waitForJob();
    return requestLog.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    const component = Qt.createComponent("file://" + shared.pluginDir + "/Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(root, {
                                    pluginApi: shared
                                  });
    check(main, "actual resource Main");
    phase = "started";
  }
  function finish() {
    main.destroy();
    main = null;
    phase = "joined";
  }
  function drive() {
    check(Date.now() - since < 15000, "finite resource phase");
    if (phase === "started" && clamshell && main.componentReady && main.outputs.length === 2 && !main.inhibitorActive) {
      if (test === "clamshell-original") {
        main.applySettings(selectedContext);
        phase = "original";
      } else {
        check(main.applySettings(selectedContext), "selected automatic admission");
        phase = "inhibited";
      }
    } else if (phase === "original" && Date.now() - since > 500) {
      check(!main.inhibitorActive && !main.enabled, "original ignored selected enabled/regex/who");
      finish();
    } else if (phase === "inhibited" && main.inhibitorActive && main.inhibitorPid > 0) {
      check(main.externalPresent && main.inhibitorWho === "selected-who", "selected classifier and who");
      check(rows().some(row => row.endpoint === "systemd-inhibit" && row.argv.indexOf("--who=selected-who") !== -1), "actual inhibitor started");
      check(toasts.length === 1 && toasts[0] === "notify.on", "actual admitted notification");
      if (test === "clamshell-policy") {
        check(main.toggle(selected) === "off", "originating toggle off");
        check(selected.pluginSettings.enabled === false && shared.pluginSettings.enabled === false, "only selected preference toggled");
        check(messages.join(",") === "selected-save", "only originating writer");
        phase = "off";
      } else if (test === "clamshell-replacement") {
        barrier.setText("hold");
        barrier.waitForJob();
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  inhibitorWho: "replacement-who",
                                                  internalConnectorRegex: "^HDMI",
                                                  notify: false
                                                });
        phase = "replacing";
      } else {
        selectedContext.live = false;
        phase = "retiring";
      }
    } else if (phase === "off" && !main.inhibitorActive && Date.now() - since > 200) {
      check(toasts.join(",") === "notify.on,notify.off", "originating completion notification");
      finish();
    } else if (phase === "replacing" && Date.now() - since > 500) {
      check(rows().filter(row => row.kind === "start" && row.endpoint === "systemd-inhibit").length === 1, "replacement waits for old inhibitor exit");
      release.setText("release");
      release.waitForJob();
      phase = "replaced";
    } else if (phase === "replaced" && rows().some(row => row.kind === "start" && row.endpoint === "systemd-inhibit" && row.argv.indexOf("--who=replacement-who") !== -1)) {
      check(main.outputs.filter(row => row.internal)[0].name === "HDMI-A-1", "selected live regex reclassifies common outputs");
      check(toasts.join(",") === "notify.on,notify.off", "old completion retains admitted notify policy; replacement stays quiet");
      finish();
    } else if (phase === "retiring" && !main.inhibitorActive && Date.now() - since > 400) {
      check(main.outputs.length === 2 && !main.enabled, "retirement stops policy not common observation");
      check(toasts.length === 1, "retired policy cannot notify");
      finish();
    } else if (phase === "started" && !clamshell && main.serviceRunning) {
      if (test === "agent-http") {
        httpBarrier.setText("hold");
        httpBarrier.waitForJob();
      }
      if (test === "agent-failure") {
        httpFailure.setText("fail");
        httpFailure.waitForJob();
      }
      check(main.restartService(selectedContext), "selected daemon admission");
      if (test === "agent-delay") {
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  port: ports()[2],
                                                  token: "later-token"
                                                });
      }
      if (test === "agent-retirement")
        selectedContext.live = false;
      phase = "agent-selected";
    } else if (phase === "agent-selected" && test === "agent-retirement" && Date.now() - since > 700) {
      check(!rows().some(row => row.kind === "start" && row.port === ports()[1]), "retired queued restart never starts");
      finish();
    } else if (phase === "agent-selected" && test === "agent-failure" && main.serviceError.length > 0 && Date.now() - since > 1200) {
      check(main.runningCount === 0, "HTTP failure cannot publish a snapshot");
      httpFailure.setText("");
      httpFailure.waitForJob();
      check(main.refresh(selectedContext), "explicit selected Retry");
      phase = "failure-observed";
    } else if (phase === "failure-observed" && main.serviceRunning && main.runningCount === ports()[1])
      finish();
    else if (phase === "agent-selected" && test === "agent-http" && rows().some(row => row.kind === "request" && row.port === ports()[1])) {
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                port: ports()[2]
                                              });
      check(main.restartService(selectedContext), "replacement source admitted");
      phase = "agent-replaced";
    } else if (phase === "agent-replaced" && main.serviceRunning && main.runningCount === ports()[2]) {
      httpRelease.setText("release");
      httpRelease.waitForJob();
      phase = "old-released";
    } else if (phase === "old-released" && Date.now() - since > 500) {
      check(main.runningCount === ports()[2], "held old response cannot overwrite replacement");
      finish();
    } else if (phase === "agent-selected" && main.serviceRunning && (test === "agent-delay" || test === "agent-polling")) {
      check(main.port === ports()[1] && main.runningCount === ports()[1], "captured delayed service port reaches snapshot");
      if (test === "agent-polling") {
        const first = main.settingsConsumerFor(selectedContext), second = main.settingsConsumerFor(selectedContext);
        check(first === second && first.sourceInterval === 1 && first.interval === 1000, "context identity and original int-seconds admission");
        selectedContext.live = false;
        phase = "poll-retired";
      } else {
        check(main.refreshAndPrune(sharedContext), "common prune admitted from another view");
        phase = "pruning";
      }
    } else if (phase === "pruning" && rows().some(row => row.kind === "request" && row.method === "POST")) {
      const request = rows().filter(row => row.kind === "request" && row.method === "POST").pop();
      check(request.port === ports()[1] && request.token === "Bearer synthetic-selected", "prune retains active service endpoint and credentials despite later caller values");
      finish();
    } else if (phase === "poll-retired" && Date.now() - since > 400) {
      check(!main.serviceRunning && main._settingsConsumers.size === 1, "retired client and admitted service stop without removing shared poller");
      finish();
    } else if (phase === "joined" && Date.now() - since > 400) {
      driver.stop();
      console.log("RESOURCE_LIFETIME: PASS " + test);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toasts.push(description);
    }
  }
  SettingsBootstrap {}
  Timer {
    id: driver
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        driver.stop();
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Component.onCompleted: begin()
}
