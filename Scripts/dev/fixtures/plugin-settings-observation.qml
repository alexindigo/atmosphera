// Explicit captured contexts and real children, not native instance/page proof.
import QtQuick
import Quickshell
import Quickshell.Io
import "Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_OBSERVATION_PLUGIN")
  readonly property bool oldRed: Quickshell.env("PHA_OBSERVATION_OLD_RED") === "1"
  readonly property bool cancelStarting: Quickshell.env("PHA_OBSERVATION_CANCEL_STARTING") === "1"
  readonly property string heldStage: Quickshell.env("PHA_OBSERVATION_HOLD_STAGE")
  readonly property bool receiveHandoff: Quickshell.env("PHA_OBSERVATION_HANDOFF") === "1"
  readonly property bool extraLifetime: Quickshell.env("PHA_OBSERVATION_EXTRA_LIFETIME") === "1"
  property var peerApi: null
  property var peerClient: null
  property var peerPanel: null
  property var secondPanel: null
  property var previousObservation: null
  property double retirementStarted: 0
  FileView {
    id: logHeld
    path: root.caseDir + "/log-held"
    blockLoading: true
  }
  Process {
    id: holdFlag
  }
  property var replacement: null
  property bool stageProcessRetired: false
  property bool startupCancelled: false
  property double cancelledAt: 0
  property var data: null
  property var main: null
  property var shared: null
  property var selected: null
  property var client: null
  property var sharedClient: null
  property var selectedContext: null
  property var bar: null
  property var panel: null
  property var sharedBar: null
  property var toasts: []
  readonly property string caseDir: Quickshell.env("PHA_OBSERVATION_CASE")
  property int phase: 0
  property double started: Date.now()
  FileView {
    id: input
    path: Quickshell.env("PHA_OBSERVATION_CASE") + "/input.json"
    blockLoading: true
  }
  FileView {
    id: held
    path: root.caseDir + (root.plugin === "tailscale" ? "/scan-held" : "/action-held")
    blockLoading: true
  }
  FileView {
    id: received
    path: root.caseDir + "/receive-original/received.txt"
    blockLoading: true
  }
  FileView {
    id: stageHeld
    path: root.caseDir + "/stage-held"
    blockLoading: true
  }
  FileView {
    id: replacementReceived
    path: root.caseDir + "/receive-replacement/received.txt"
    blockLoading: true
  }
  Process {
    id: release
    command: ["touch", root.caseDir + "/release"]
  }
  Process {
    id: retirementProbe
    command: ["python3", root.caseDir + "/bin/stage-retirement-probe"]
    onExited: function (code) {
      if (code === 0)
        root.stageProcessRetired = true;
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toasts = root.toasts.concat([
                                         {
                                           title: title,
                                           description: description,
                                           type: type
                                         }
                                       ]);
    }
  }
  Component {
    id: apiFactory
    QtObject {
      id: api
      property var manifest: root.data.manifest
      property string pluginDir: root.data.directory
      required property var pluginSettings
      property var mainInstance: root.main
      property bool alive: true
      readonly property var settingsView: pluginSettings
      readonly property var settingsContext: Read.context(function () {
        return api.pluginSettings;
      }, function () {
        return api.alive;
      })
      function tr(key, params) {
        return key;
      }
      function trp(key, count) {
        return key + " " + count;
      }
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 900
    implicitHeight: 800
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("OBSERVATION_ASSERT: " + plugin + "/" + phase + ": " + message);
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
  function create(file, properties) {
    var component = Qt.createComponent("file://" + data.directory + "/" + file);
    check(component.status === Component.Ready, component.errorString());
    var item = component.createObject(content, properties);
    check(item !== null, "actual " + file + " constructs");
    return item;
  }
  function hookStarting(object, seen) {
    if (!object || seen.has(object))
      return;
    seen.add(object);
    if (object.childrenChanged)
      object.childrenChanged.connect(function () {
        for (var child of object.children)
          hookStarting(child, seen);
      });
    if (object.commandChanged && object.processIdChanged) {
      object.commandChanged.connect(function () {
        const argv = Array.from(object.command || []);
        if (argv.indexOf("file") < 0 || argv.indexOf("get") < 0)
          return;
        object.processIdChanged.connect(function () {
          if (object.processId > 0 && !root.startupCancelled) {
            root.startupCancelled = true;
            root.selected.alive = false;
            root.cancelledAt = Date.now();
            root.phase = 6;
          }
        });
      });
    }
    for (var list of [object.data, object.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list)
        hookStarting(child, seen);
    }
  }
  function begin() {
    input.waitForJob();
    data = JSON.parse(input.text());
    shared = apiFactory.createObject(root, {
                                       pluginSettings: data.shared
                                     });
    selected = apiFactory.createObject(root, {
                                         pluginSettings: data.selected
                                       });
    main = create("Main.qml", {
                    pluginApi: shared
                  });
    if (cancelStarting)
      hookStarting(main, new Set());
    if (!oldRed) {
      sharedClient = main.settingsConsumerFor(shared.settingsContext);
      selectedContext = selected.settingsContext;
      client = main.settingsConsumerFor(selectedContext);
      check(client && client !== sharedClient, "distinct selected policy clients");
      check(client === main.settingsConsumerFor(selectedContext), "same logical context shares client");
    }
    bar = create("BarWidget.qml", {
                   pluginApi: selected,
                   screen: Quickshell.screens[0]
                 });
    if (!oldRed) {
      panel = create("Panel.qml", {
                       pluginApi: selected,
                       width: 700,
                       height: 750
                     });
      sharedBar = create("BarWidget.qml", {
                           pluginApi: shared,
                           screen: Quickshell.screens[0]
                         });
    }
    phase = 1;
  }
  function observe() {
    if (plugin === "port-monitor") {
      if (main.portCount !== 3)
        return false;
      if (oldRed)
        check(bar.portCount === 2, "original shared observation does not apply selected policy");
      check(bar.mainInstance === client && panel.mainInstance === client, "actual Bar and Panel select exact client");
      check(client.portCount === 2 && sharedClient.portCount === 3, "unfiltered observation supplies distinct selected port projections");
      check(find(bar, item => item.text === "2") && find(panel, item => item.text === "selected-http" || String(item.text).indexOf("processInfo") >= 0), "actual child Text consumes selected ports");
      check(client.interval === 1500, "fractional seconds retain post-scale int policy");
    } else if (plugin === "mullvad") {
      if (main.state !== "connected")
        return false;
      if (oldRed)
        check(bar.main.showCityName, "original shared observation does not apply selected policy");
      check(bar.main === client && panel.main === client && client.currentLocation === main.currentLocation, "actual selected Bar/Panel share one daemon observation");
      check(client.showCityName && !sharedClient.showCityName && client.favoriteCountries[0] === "se" && client.expiryWarningDays === 30, "selected display/favorite/expiry policy");
      check(find(bar, item => item.text === "Controlled City" && item.visible), "actual selected city Text is visible");
      check(client.interval === 1500, "selected millisecond schedule");
    } else if (plugin === "netbird") {
      if (!main.netbirdRunning)
        return false;
      if (oldRed)
        check(bar.mainInstance.compactMode, "original shared observation does not apply selected policy");
      if (client.peerPings["100.64.0.2"] !== "12.3")
        return false;
      check(bar.mainInstance === client && panel.mainInstance === client, "actual NetBird views select client");
      check(client.compactMode && !sharedClient.compactMode && client.interval === 1500, "selected display and polling");
      check(!main.showPing && main.pingRequested && client.showPing, "selected ping demand reaches the common query owner");
      check(panel.terminalCommand === "ghostty" && main.detectedTerminal === "ghostty", "manual plugin terminal never masquerades as common discovery");
      check(panel.adminConsoleUrl === "https://selected.invalid", "selected URL wins over common detected URL");
      check(find(panel, item => item.text === "100.64.0.1"), "actual Panel Text sees common physical observation");
      if (extraLifetime) {
        beginExtraLifetime();
        return true;
      }
    } else if (plugin === "tailscale") {
      if (!main.tailscaleRunning)
        return false;
      check(bar.mainInstance === client && panel.mainInstance === client && client.compactMode && !sharedClient.compactMode, "actual Tailscale views select policy over common daemon state");
      check(client.taildropEnabled && !sharedClient.taildropEnabled && client.interval === 1500, "selected producer admission and schedule");
      client.startTaildropReceive();
      phase = heldStage ? 7 : 3;
      return true;
    } else if (plugin === "openvpn3") {
      if (main.sessionList.length !== 1 || main.sessionLogs.length === 0)
        return false;
      check(bar.main === client && panel.main === client && client.pollInterval === 1500 && sharedClient.pollInterval === 8000, "actual OpenVPN views and typed selected two-tier polling");
      check(main.panelOpen && main.logStreamActive && client.panelOpen, "selected Panel demand reaches common heavy/log owner");
      check(find(panel, item => item.text === "Controlled VPN"), "actual selected Panel session Text");
      if (extraLifetime) {
        beginExtraLifetime();
        return true;
      }
      client.connectTo("/controlled/failure");
      phase = 3;
      return true;
    } else if (plugin === "amd-gpu-monitor") {
      if (!client.observation?.available || !sharedClient.observation?.available)
        return false;
      check(bar.settingsClient === client && panel.settingsClient === client && bar.mon === client.observation, "actual GPU consumers select observation lease");
      check(client.deviceIndex === 1 && sharedClient.deviceIndex === 0 && client.observation.productName === "Controlled GPU 1" && sharedClient.observation.productName === "Controlled GPU 0", "floor-admitted selected device result and history");
      check(client.observation.gpuUseHistory.slice(-1)[0] === 11 && sharedClient.observation.gpuUseHistory.slice(-1)[0] === 10, "histories retain the correct device identity");
      check(find(panel, item => item.text === "Controlled GPU 1"), "actual selected GPU name Text");
      if (extraLifetime) {
        beginExtraLifetime();
        return true;
      }
    } else if (plugin === "battery-monitor-plus") {
      if (!client.observation?.sysfsOk || !sharedClient.observation?.sysfsOk)
        return false;
      check(bar.settingsClient === client && panel.settingsClient === client && bar.monitor === client.observation, "actual battery consumers select observation lease");
      check(client.interval === 1000 && client.observation.sysfsPowerWatts === 22.2 && sharedClient.observation.sysfsPowerWatts === 11.1, "old clamped int boundary and selected helper result");
      check(client.observation.sysfsSource === "selected-battery" && client.observation.isChargingHardware, "selected helper identity and status");
      check(find(panel, item => String(item.text).indexOf("22.2") >= 0), "actual selected battery power Text");
    }
    selected.alive = false;
    phase = 2;
    return true;
  }
  function driveAction() {
    held.reload();
    held.waitForJob();
    if (!held.text())
      return;
    if (plugin === "tailscale") {
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                taildropEnabled: false,
                                                taildropDownloadDir: caseDir + "/receive-replacement",
                                                taildropReceiveMode: "pkexec"
                                              });
      check(main._taildropRequest.directory === caseDir + "/receive-original" && main._taildropRequest.mode === "operator", "producer owns admitted policy across settings replacement");
    } else {
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                showNotifications: false
                                              });
      check(!client.showNotifications && main._connectProc.notifyErrors, "admitted action retains originating notification policy");
    }
    release.running = true;
    phase = 4;
  }
  function setHold(stage) {
    holdFlag.command = ["touch", caseDir + "/" + stage + "-hold"];
    holdFlag.running = true;
  }
  function beginExtraLifetime() {
    peerApi = apiFactory.createObject(root, {
                                        pluginSettings: Object.assign({}, data.selected)
                                      });
    peerClient = main.settingsConsumerFor(peerApi.settingsContext);
    if (plugin === "amd-gpu-monitor") {
      secondPanel = create("BarWidget.qml", {
                             pluginApi: selected,
                             screen: Quickshell.screens[0]
                           });
      peerPanel = create("Panel.qml", {
                           pluginApi: peerApi,
                           width: 700,
                           height: 750
                         });
      check(secondPanel.settingsClient === client && client._pollers.size === 3, "same-context GPU views share one client registration");
      check(peerClient !== client && peerClient.observation === client.observation && main._observations.size === 2, "same-device GPU contexts share one physical history observer");
      previousObservation = client.observation;
      setHold("gpu-1");
    } else if (plugin === "netbird") {
      peerApi.pluginSettings = Object.assign({}, peerApi.pluginSettings, {
                                               terminalCommand: "gnome-terminal-controlled",
                                               pingCount: 7
                                             });
      peerPanel = create("Panel.qml", {
                           pluginApi: peerApi,
                           width: 700,
                           height: 750
                         });
      panel.executePeerAction("ssh", main.peerList[0]);
      peerPanel.executePeerAction("ping", main.peerList[0]);
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                terminalCommand: "selected-terminal",
                                                managementUrl: "replacement.invalid",
                                                showPing: false
                                              });
      panel.executePeerAction("ssh", main.peerList[0]);
      check(panel.adminConsoleUrl === "https://replacement.invalid" && main.detectedTerminal === "ghostty" && peerPanel.terminalCommand === "gnome-terminal-controlled", "replacement selected URL/terminal never changes common discovery or sibling actions");
      check(main.pingRequested && peerClient.showPing && !client.showPing && !main.showPing, "remaining context retains common ping demand");
      setHold("ping");
    } else {
      secondPanel = create("Panel.qml", {
                             pluginApi: selected,
                             width: 700,
                             height: 750
                           });
      peerApi.pluginSettings = Object.assign({}, peerApi.pluginSettings, {
                                               pollInterval: 2.25,
                                               showNotifications: false
                                             });
      peerPanel = create("Panel.qml", {
                           pluginApi: peerApi,
                           width: 700,
                           height: 750
                         });
      check(client._panels.size === 2 && peerClient._panels.size === 1 && peerClient.pollInterval === 2250, "multiple actual Panels aggregate per-context demand without merging typed schedules");
      client.connectTo("/controlled/failure");
    }
    phase = 10;
  }
  function driveExtraLifetime() {
    if (plugin === "amd-gpu-monitor") {
      stageHeld.reload();
      stageHeld.waitForJob();
      if (phase === 10) {
        if (!stageHeld.text())
          return;
        check(JSON.parse(stageHeld.text()).stage === "gpu-1", "held old card query identity");
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  deviceIndex: 2
                                                });
        phase = 11;
      } else if (phase === 11) {
        if (!client.observation?.available)
          return;
        check(client.observation !== previousObservation && peerClient.observation === previousObservation && main._observations.has(1), "source handoff transfers selected registrations while same-device peer retains its lease");
        check(bar.mon === client.observation && panel.mon === client.observation && secondPanel.mon === client.observation && client.observation.productName === "Controlled GPU 2" && client.observation.gpuUseHistory.every(value => value === 0 || value === 12) && client.observation.gpuUseHistory.slice(-1)[0] === 12,
              "actual replacement GPU child and history never borrow held old card data");
        check(find(panel, item => item.text === "Controlled GPU 2"), "actual replacement GPU Text");
        peerApi.alive = false;
        retirementStarted = Date.now();
        phase = 12;
      } else if (phase === 12) {
        if (!retirementObserved())
          return;
        check(!main._observations.has(1), "last old GPU lease retires its observer");
        stageProcessRetired = false;
        setHold("gpu-2");
        phase = 13;
      } else if (phase === 13) {
        if (JSON.parse(stageHeld.text()).stage !== "gpu-2")
          return;
        selected.alive = false;
        retirementStarted = Date.now();
        phase = 14;
      } else if (phase === 14) {
        if (!retirementObserved())
          return;
        check(main._observations.size === 1 && main._observations.has(0), "last selected GPU owner retires only its held process/history");
        phase = 2;
      }
    } else if (plugin === "netbird") {
      if (phase === 10) {
        stageHeld.reload();
        stageHeld.waitForJob();
        if (!stageHeld.text())
          return;
        peerApi.alive = false;
        retirementStarted = Date.now();
        phase = 11;
      } else if (phase === 11) {
        if (!retirementObserved())
          return;
        check(!main.pingRequested && main.currentPingIp === "" && main.pingQueue.length === 0 && !main.showPing, "last ping context retires held query without reviving its queue");
        selected.alive = false;
        phase = 2;
      }
    } else {
      if (phase === 10) {
        held.reload();
        held.waitForJob();
        if (!held.text())
          return;
        logHeld.reload();
        logHeld.waitForJob();
        if (!logHeld.text())
          return;
        check(main._logProc.processId === JSON.parse(logHeld.text()).pid, "all actual Panels share the exact common log process");
        panel.destroy();
        panel = null;
        phase = 11;
      } else if (phase === 11) {
        if (client._panels.size !== 1)
          return;
        check(main.panelOpen && main.logStreamActive && main._logProc.processId === JSON.parse(logHeld.text()).pid, "one Panel destruction retains other views and the exact log stream");
        secondPanel.visible = false;
        phase = 12;
      } else if (phase === 12) {
        if (client.panelOpen)
          return;
        check(peerClient.panelOpen && main.panelOpen && main.logStreamActive, "another context retains common heavy/log demand");
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  showNotifications: false
                                                });
        selected.alive = false;
        check(main._connectProc.running && main._connectProc.notifyErrors, "admitted shared action retains captured notification policy after originating retirement");
        peerPanel.visible = false;
        retirementProbe.command = ["python3", caseDir + "/bin/stage-retirement-probe", "log-held"];
        retirementStarted = Date.now();
        phase = 13;
      } else if (phase === 13) {
        if (!retirementObserved())
          return;
        check(!main.panelOpen && !main.logStreamActive && !main._logProc.running, "last actual Panel retires common log demand before held action release");
        release.running = true;
        phase = 14;
      } else if (phase === 14) {
        if (main.isPending("/controlled/failure"))
          return;
        check(toasts.filter(row => row.title === "errors.connect" && row.type === "error").length === 1, "captured originating notification reaches actual toast after shared action settlement");
        peerApi.alive = false;
        phase = 2;
      }
    }
  }
  function retirementObserved() {
    check(Date.now() - retirementStarted < 2400 || stageProcessRetired, "held observation process retires before source release");
    if (!stageProcessRetired && !retirementProbe.running)
      retirementProbe.running = true;
    return stageProcessRetired;
  }
  Timer {
    interval: 60
    running: true
    repeat: true
    onTriggered: {
      try {
        check(Date.now() - root.started < 18000, "finite observation deadline");
        if (root.phase === 0 && Settings.isLoaded)
          root.begin();
        else if (root.phase === 1)
          root.observe();
        else if (root.phase === 3)
          root.driveAction();
        else if (root.phase >= 10 && root.phase <= 14)
          root.driveExtraLifetime();
        else if (root.phase === 4) {
          if (root.plugin === "tailscale") {
            received.reload();
            received.waitForJob();
            if (!received.text() || root.main._taildropRequest)
              return;
            root.main.needsLogin = true;
            root.client.loginTailscale();
          } else {
            if (root.main.isPending("/controlled/failure"))
              return;
            check(root.toasts.filter(row => row.title === "errors.connect" && row.type === "error").length === 1, "actual toast consumer receives captured action failure");
            root.panel.destroy();
            root.panel = null;
          }
          root.phase = 5;
        } else if (root.phase === 5) {
          if (root.plugin === "openvpn3")
            check(!root.main.panelOpen && !root.main.logStreamActive && !root.main._logProc.running, "last selected Panel retires the one log stream");
          root.selected.alive = false;
          root.phase = 2;
        } else if (root.phase === 6) {
          if (Date.now() - root.cancelledAt < 180)
            return;
          check(root.startupCancelled && root.main._taildropRequest === null && root.main.taildropState === "idle", "retired receive startup never revives state or dereferences a cleared request");
          check(root.toasts.length === 0, "cancelled receive has no completion toast");
          console.log("OBSERVATION_CONTEXT: PASS " + root.plugin);
          Qt.exit(0);
        } else if (root.phase === 7) {
          stageHeld.reload();
          stageHeld.waitForJob();
          if (!stageHeld.text())
            return;
          const oldOperation = root.main._taildropOperation;
          const oldCompletion = oldOperation?.completed;
          root.selected.alive = false;
          check(root.main._taildropRequest === null && root.main.taildropState === "idle", "held stage retirement cancels originating receive");
          if (root.receiveHandoff) {
            root.replacement = apiFactory.createObject(root, {
                                                         pluginSettings: Object.assign({}, root.data.selected, {
                                                                                         taildropDownloadDir: root.caseDir + "/receive-replacement"
                                                                                       })
                                                       });
            const next = root.main.settingsConsumerFor(root.replacement.settingsContext);
            root.bar.pluginApi = root.replacement;
            root.panel.pluginApi = root.replacement;
            next.startTaildropReceive();
            const nextOperation = root.main._taildropOperation;
            oldCompletion(oldOperation, {
                            ok: true,
                            files: ["obsolete-injected.txt"]
                          });
            check(nextOperation && root.main._taildropOperation === nextOperation && root.main.taildropState === "receiving" && root.toasts.length === 0, "late originating completion cannot settle replacement receive");
          }
          root.phase = 8;
        } else if (root.phase === 8) {
          if (!root.stageProcessRetired) {
            if (!retirementProbe.running)
              retirementProbe.running = true;
            return;
          }
          if (root.receiveHandoff) {
            replacementReceived.reload();
            replacementReceived.waitForJob();
            if (!replacementReceived.text() || root.main._taildropRequest)
              return;
            check(root.toasts.length === 1 && root.toasts[0].description === "received.txt", "only actual replacement receive completes and toasts");
            root.replacement.alive = false;
          }
          check(root.main._taildropRequest === null && root.main.taildropState === "idle" && (root.receiveHandoff || root.toasts.length === 0), "retired stage cannot complete or toast");
          console.log("OBSERVATION_CONTEXT: PASS " + root.plugin);
          Qt.exit(0);
        } else if (root.phase === 2) {
          check(!root.main._settingsConsumers.has(root.selectedContext) && root.main.settingsConsumerFor(root.selectedContext) === null, "retired policy client cannot be reacquired");
          if (root.plugin === "netbird")
            check(!root.main.pingRequested, "last selected ping demand retires");
          console.log("OBSERVATION_CONTEXT: PASS " + root.plugin);
          Qt.exit(0);
        }
      } catch (error) {
        console.error(String(error) + "\n" + (error.stack || ""));
        Qt.exit(2);
      }
    }
  }
}
