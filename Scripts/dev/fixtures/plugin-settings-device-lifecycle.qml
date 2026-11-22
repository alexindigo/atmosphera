import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string base: Quickshell.env("PHA_DEVICE_CASE")
  readonly property string scenario: Quickshell.env("PHA_DEVICE_SCENARIO")
  readonly property bool gpu: scenario.startsWith("gpu-")
  property var main: null
  property var client: null
  property var oldRows: []
  property int before: 0
  property int notices: 0
  property int notifications: 0
  property bool started: false
  property string phase: "begin"
  property double since: Date.now()
  onPhaseChanged: since = Date.now()
  QtObject {
    id: sharedApi
    property string pluginId: "device-lifetime"
    property var manifest: ({
                              version: "fixture",
                              metadata: {
                                defaultSettings: {
                                  autoMount: false,
                                  showNotifications: true,
                                  fileBrowser: "dolphin",
                                  terminalCommand: "kitty",
                                  debug: true,
                                  rogcc: {
                                    listenToNotifications: false
                                  },
                                  supergfxctl: {
                                    patchPending: true,
                                    polling: false,
                                    pollingInterval: 3000
                                  }
                                }
                              }
                            })
    property var pluginSettings: manifest.metadata.defaultSettings
    property var settingsContext: sharedContext
    function tr(key) {
      return key;
    }
  }
  QtObject {
    id: selectedApi
    property var pluginSettings: ({
                                    autoMount: true,
                                    showNotifications: false,
                                    fileBrowser: "yazi",
                                    terminalCommand: "wezterm",
                                    debug: true,
                                    supergfxctl: {
                                      patchPending: false,
                                      polling: false,
                                      pollingInterval: 3000
                                    }
                                  })
  }
  QtObject {
    id: sharedContext
    readonly property var settingsView: sharedApi.pluginSettings
    function current() {
      return true;
    }
  }
  QtObject {
    id: selectedContext
    property bool alive: true
    readonly property var settingsView: selectedApi.pluginSettings
    function current() {
      return alive;
    }
  }
  QtObject {
    id: typedOracle
    readonly property var input: selectedApi.pluginSettings.supergfxctl
    readonly property bool polling: input.polling
    readonly property bool patchPending: input.patchPending
    readonly property int interval: input.pollingInterval
  }
  FileView {
    id: requests
    path: root.base + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: release
  }
  Process {
    id: peer
    command: ["/usr/bin/python3", root.base + "/peer.py"]
    stdout: StdioCollector {
      id: peerOutput
    }
    onExited: code => {
      if (code !== 0)
        root.fail("real private notification call failed");
      else
        root.phase = "notified";
    }
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.notices++;
    }
  }
  Connections {
    target: root.gpu ? root.main?.notificationListener?.target ?? null : null
    function onNotification(notification) {
      root.check(notification.summary === "device-policy-probe", "actual private notification payload");
      root.notifications++;
    }
  }
  Item {
    id: content
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("DEVICE_LIFETIME_ASSERT: " + scenario + "/" + phase + ": " + message);
  }
  function fail(error) {
    driver.stop();
    console.error(String(error));
    Qt.exit(2);
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return requests.text().trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function match(name, predicate) {
    return rows().filter(row => row.endpoint === name && (!predicate || predicate(row)));
  }
  function patch(values) {
    selectedApi.pluginSettings = Object.assign({}, selectedApi.pluginSettings, values);
  }
  function releaseTag(tag) {
    release.command = ["touch", base + "/release-" + tag];
    release.running = true;
  }
  function pass() {
    driver.stop();
    console.log("DEVICE_LIFETIME: PASS " + scenario);
    Qt.exit(0);
  }
  function begin() {
    if (started || !Settings.isLoaded)
      return;
    started = true;
    const component = Qt.createComponent("file://" + base + "/plugin/" + (gpu ? "src/" : "") + "Main.qml");
    check(component.status === Component.Ready, component.errorString());
    main = component.createObject(content, {
                                    pluginApi: sharedApi
                                  });
    check(main, "actual Main constructs");
    phase = "initial";
  }
  function drive() {
    if (phase === "begin")
      return;
    check(Date.now() - since < 18000, "finite device lifetime phase");
    if (phase === "initial") {
      if (Date.now() - since < 500 || (gpu ? main.busy || !main.available : main.loading || main.devices.length !== 1))
        return;
      if (!gpu) {
        check(main.selectedContext === null, "construction cannot choose automatic policy");
        if (scenario.startsWith("usb-auto")) {
          check(main.activatePolicy(selectedContext), "admit automatic policy");
          releaseTag("udev");
          phase = "udev";
        } else if (scenario === "usb-browser") {
          main.openInFileBrowser(base + "/mounted", selectedContext);
          phase = "browser";
        } else {
          if (scenario === "usb-unmount")
            main.unmountDevice("/dev/fixture-usb", "Fixture USB", selectedContext);
          else if (scenario === "usb-eject")
            main.ejectDevice("/dev/fixture-usb", "/dev/fixture-usb", "Fixture USB", selectedContext);
          else
            main.mountDevice("/dev/fixture-usb", "Fixture USB", selectedContext);
          phase = "usb-held";
        }
      } else {
        client = main.settingsConsumerFor(selectedContext);
        check(client === main.settingsConsumerFor(selectedContext), "renderers share one typed client");
        if (scenario === "gpu-polling") {
          patch({
                  supergfxctl: {
                    patchPending: 0,
                    polling: 1,
                    pollingInterval: 150.6
                  }
                });
          phase = "polling";
        } else if (scenario === "gpu-notification") {
          peer.running = true;
          phase = "notifying";
        } else if (scenario.startsWith("gpu-query")) {
          check(main.refresh(selectedContext), "selected query admitted");
          phase = "query-held";
        } else {
          patch({
                  supergfxctl: {
                    patchPending: true,
                    polling: false,
                    pollingInterval: 3000
                  }
                });
          check(main.setMode(0, selectedContext), "selected manual command admitted");
          phase = "mode-held";
        }
      }
    } else if (phase === "udev" && main._debouncePolicy) {
      check(main._debouncePolicy.context === selectedContext, "udev captures admitted automatic context");
      before = match("lsblk").length;
      if (scenario === "usb-auto-retire")
        selectedContext.alive = false;
      else {
        patch({
                autoMount: false
              });
        main.activatePolicy(sharedContext);
      }
      phase = "automatic";
    } else if (phase === "automatic" && Date.now() - since > 1100) {
      check(match("lsblk").length > before, "observation survives automatic policy retirement");
      check(match("udisksctl").length === (scenario === "usb-auto-retire" ? 0 : 1), "captured automatic policy reaches mount endpoint");
      if (scenario === "usb-auto-retire")
        pass();
      else {
        releaseTag("action");
        phase = "automatic-completed";
      }
    } else if (phase === "automatic-completed" && Date.now() - since > 300) {
      check(notices === 0, "captured automatic policy reaches mount endpoint");
      selectedContext.alive = false;
      pass();
    } else if (phase === "browser" && Date.now() - since > 300) {
      check(match("wezterm", row => JSON.stringify(row.argv) === JSON.stringify(["--", "yazi", base + "/mounted"])).length === 1, "selected terminal flag and literal browser target");
      selectedContext.alive = false;
      before = rows().length;
      main.openInFileBrowser(base + "/mounted", selectedContext);
      phase = "browser-retired";
    } else if (phase === "browser-retired" && Date.now() - since > 200) {
      check(rows().length === before, "retired browser origin refused");
      pass();
    } else if (phase === "usb-held") {
      const held = match(scenario === "usb-eject" ? "sh" : "udisksctl");
      if (!held.length)
        return;
      oldRows = held;
      before = match("lsblk").length;
      if (scenario === "usb-action-retire")
        selectedContext.alive = false;
      else
        patch({
                showNotifications: true
              });
      releaseTag("action");
      phase = "usb-completed";
    } else if (phase === "usb-completed" && Date.now() - since > 1100) {
      check(notices === 0, "captured USB completion notification policy");
      check(match("lsblk").length === before + (scenario === "usb-action-retire" ? 0 : 1), "completion debounce and retired follow-up admission");
      pass();
    } else if (phase === "polling" && Date.now() - since > 500) {
      console.log("DEVICE_TYPED_DOMAIN " + JSON.stringify({
                                                            polling: client.polling,
                                                            patchPending: client.patchPending,
                                                            interval: client.pollingInterval,
                                                            reference: typedOracle.interval
                                                          }));
      check(client.polling === typedOracle.polling && client.patchPending === typedOracle.patchPending && client.pollingInterval === typedOracle.interval && client.pollingTimer.interval === typedOracle.interval, "original QML bool/int typed polling domain");
      check(match("supergfxctl").length >= 3, "actual typed schedule reaches common CLI consumer");
      selectedContext.alive = false;
      before = match("supergfxctl").length;
      phase = "polling-retired";
    } else if (phase === "polling-retired" && Date.now() - since > 450) {
      check(!main._settingsConsumers.has(selectedContext) && match("supergfxctl").length === before, "retired typed client stops schedule");
      pass();
    } else if (phase === "query-held" && match("supergfxctl").length >= 2) {
      before = match("supergfxctl").length;
      if (scenario === "gpu-query-retire")
        selectedContext.alive = false;
      else
        patch({
                supergfxctl: {
                  patchPending: true,
                  polling: false,
                  pollingInterval: 3000
                }
              });
      releaseTag("query");
      phase = "query-completed";
    } else if (phase === "query-completed" && Date.now() - since > 500 && !main.busy) {
      check(main.pendingAction === 4 && main.pendingMode === (scenario === "gpu-query-retire" ? 6 : 0), "captured parser policy reaches pending state");
      check(match("supergfxctl").length === before, "retired query cannot enqueue follow-up");
      pass();
    } else if (phase === "mode-held" && match("supergfxctl", row => row.argv[0] === "--mode").length) {
      before = match("supergfxctl").length;
      if (scenario === "gpu-mode-retire")
        selectedContext.alive = false;
      else
        patch({
                supergfxctl: {
                  patchPending: false,
                  polling: false,
                  pollingInterval: 3000
                }
              });
      releaseTag("action");
      phase = "mode-completed";
    } else if (phase === "mode-completed" && Date.now() - since > 500 && !main.busy) {
      if (scenario === "gpu-mode-retire")
        check(match("supergfxctl").length === before, "retired mode cannot start query");
      else {
        check(match("supergfxctl").length === before + 1 && main._refreshPolicy.context === selectedContext && main._refreshPolicy.patchPending, "mode follow-up retains captured policy");
        check(main.mode === 1 && main.pendingMode === 0 && main.pendingAction === 0 && main.sgfx.manualRequest.targetMode === 0, "admitted manual mode survives daemon observations");
      }
      pass();
    } else if (phase === "notified" && Date.now() - since > 200) {
      check(notifications === 1 && JSON.parse(peerOutput.text).privateBus, "one real private NotificationServer consumer");
      selectedContext.alive = false;
      check(main.notificationListener.target, "shared notification owner survives selected retirement");
      main.destroy();
      main = null;
      phase = "notification-retired";
    } else if (phase === "notification-retired" && Date.now() - since > 200)
      pass();
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.begin();
    }
  }
  SettingsBootstrap {}
  Timer {
    id: driver
    interval: 20
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
