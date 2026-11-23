// Controlled explicit contexts; separate from native placement acceptance.
import QtQuick
import Quickshell
import Quickshell.Io
import "Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.UI

ShellRoot {
  id: root
  readonly property string plugin: Quickshell.env("PHA_PROJECTION_PLUGIN")
  readonly property string caseDir: Quickshell.env("PHA_PROJECTION_CASE")
  property var data: null
  property var main: null
  property var shared: null
  property var selected: null
  property var peer: null
  property var client: null
  property var peerClient: null
  property var bar: null
  property var panel: null
  property var cc: null
  property var toasts: []
  property var history: null
  property int pendingToastCount: 0
  property int phase: 0
  property double phaseTime: Date.now()
  onPhaseChanged: phaseTime = Date.now()
  FileView {
    id: input
    path: root.caseDir + "/input.json"
    blockLoading: true
  }
  FileView {
    id: requests
    path: root.caseDir + "/requests.jsonl"
    blockLoading: true
  }
  Process {
    id: snapshot
  }
  Connections {
    target: ToastService
    function onNotify(title, description, icon, type, duration, actionLabel, actionCallback) {
      root.toasts = root.toasts.concat([
                                         {
                                           title: title,
                                           icon: icon
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
      property int writes: 0
      property var lifetime: ({
                                alive: true
                              })
      Component.onDestruction: lifetime.alive = false
      readonly property var settingsContext: Read.context(lifetime, function () {
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
      function saveSettings() {
        // This explicit-context collaborator has no native property notifier.
        // Publish its changed read projection as the real native API does.
        pluginSettings = Object.assign({}, pluginSettings);
        writes++;
        return true;
      }
    }
  }
  PanelWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 850
    Item {
      id: content
      anchors.fill: parent
    }
  }
  function check(ok, message) {
    if (!ok)
      throw new Error("PROJECTION_LIFECYCLE_ASSERT: " + plugin + "/" + phase + ": " + message);
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
  function create(entry, api) {
    var component = Qt.createComponent("file://" + data.directory + "/" + data.manifest.entryPoints[entry]);
    check(component.status === Component.Ready, component.errorString());
    var properties = {
      pluginApi: api
    };
    if (entry === "barWidget" || entry === "controlCenterWidget")
      properties.screen = Quickshell.screens[0];
    var item = component.createObject(content, properties);
    check(item, "actual component constructs: " + entry);
    return item;
  }
  function begin() {
    if (phase || !Settings.isLoaded)
      return;
    input.waitForJob();
    data = JSON.parse(input.text());
    var base = Object.assign({}, data.manifest.metadata.defaultSettings);
    if (plugin === "privacy-indicator")
      Object.assign(base, {
                      enableToast: false,
                      activeColor: "secondary"
                    });
    else if (plugin === "kde-connect")
      Object.assign(base, {
                      mainDeviceId: "phone-a"
                    });
    else
      Object.assign(base, {
                      precision: 8,
                      showBarValue: true
                    });
    shared = apiFactory.createObject(content, {
                                       pluginSettings: base
                                     });
    main = create("main", shared);
    var chosen = Object.assign({}, base);
    if (plugin === "privacy-indicator")
      Object.assign(chosen, {
                      enableToast: true
                    });
    else if (plugin === "kde-connect")
      Object.assign(chosen, {
                      mainDeviceId: "phone-b"
                    });
    else
      Object.assign(chosen, {
                      precision: 2,
                      showBarValue: false
                    });
    selected = apiFactory.createObject(content, {
                                         pluginSettings: chosen
                                       });
    peer = apiFactory.createObject(content, {
                                     pluginSettings: Object.assign({}, chosen)
                                   });
    client = main.settingsConsumerFor(selected.settingsContext);
    peerClient = main.settingsConsumerFor(peer.settingsContext);
    bar = create("barWidget", selected);
    panel = create("panel", selected);
    if (plugin === "kde-connect")
      cc = create("controlCenterWidget", selected);
    phase = 1;
  }
  function mic(name, anonymous) {
    var node = {
      isStream: true,
      audio: true,
      isSink: false,
      properties: {
        "media.class": "Stream/Input/Audio",
        "application.name": anonymous ? "" : name
      }
    };
    main.updateMicrophoneState([node, node], [
                                 {
                                   source: node
                                 }
                               ]);
  }
  function rows() {
    requests.reload();
    requests.waitForJob();
    return String(requests.text()).trim().split("\n").filter(line => line).map(line => JSON.parse(line));
  }
  function drive() {
    check(Date.now() - phaseTime < 18000, "finite individual outcome deadline");
    if (!phase) {
      begin();
      return;
    }
    if (phase === 1) {
      check(bar.settingsConsumer === client && panel.settingsConsumer === client && main.settingsConsumerFor(selected.settingsContext) === client, "same-context views share one projection");
      if (plugin === "privacy-indicator") {
        if (!main.isLoaded || !main.accessHistory.some(row => row.appName === "retained-content"))
          return;
        // Freeze only fixture sampling, not product sources. The real camera
        // Process and pure microphone classifier still execute below.
        var timer = find(main, item => item.interval === 1000 && item.repeat === true && item.triggeredOnStart === true);
        check(timer, "actual single physical sampling timer");
        timer.stop();
        mic("Controlled Microphone", false);
        main.updateCameraState();
        phase = 2;
      } else if (plugin === "kde-connect") {
        if (!client.mainDevice || client.mainDevice.id !== "phone-b" || !find(panel, item => item.text === "Phone B"))
          return;
        check(cc.settingsConsumer === client && cc.tooltipText.indexOf("42%") >= 0, "actual CC selected device/battery");
        var ring = find(panel, item => item.tooltipText === "panel.find-device" && item.clicked !== undefined);
        check(ring, "actual selected ring button");
        ring.clicked();
        client.wakeUpDevice();
        // Save through the same originating capability used by the real switcher.
        check(client.selectDevice("phone-a", shared) === false && shared.writes === 0, "foreign runtime writer refused");
        check(client.selectDevice("phone-a", selected) !== false && selected.writes === 1 && shared.writes === 0, "device selection uses originating runtime writer");
        client.shareFile("phone-b", caseDir + "/literal ' file.txt");
        phase = 2;
      } else {
        client.clearAll();
        for (var action of ["1", "divide", "3"])
          client.pressButton(action);
        check(client.handleKeyEvent({
                                      text: "=",
                                      key: Qt.Key_Equal,
                                      modifiers: Qt.NoModifier
                                    }), "actual keyboard path accepts equality");
        check(main.currentInput === "0.33" && find(panel, item => item.text === "0.33"), "keyboard calculation uses originating precision");
        check(bar.badge === "" && main.currentInput === peerClient.currentInput, "selected hidden badge over one shared calculation");
        selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                  precision: 3,
                                                  showBarValue: true
                                                });
        client.pressButton("percent");
        check(main.currentInput === "0.003" && find(bar, item => item.text === "0.003"), "percent action and actual bar use selected policy");
        peerClient.clearAll();
        check(main.currentInput === "0" && client.currentInput === "0", "another context clears same calculation");
        phase = 4;
      }
    } else if (phase === 2) {
      if (plugin === "privacy-indicator") {
        if (client.camApps.indexOf("Controlled Camera") < 0)
          return;
        check(toasts.filter(row => row.icon === "microphone").length === 1 && toasts.filter(row => row.icon === "camera").length === 1, "common notification admitted once across selected contexts");
        check(client.micApps.length === 1 && peerClient.micActive, "deduplicated raw microphone observation");
        history = JSON.stringify(main.accessHistory);
        snapshot.command = ["cp", Settings.cacheDir + "privacy-history.json", caseDir + "/history-before.json"];
        snapshot.running = true;
        phase = 3;
      } else {
        var actions = rows().filter(row => row.command === "busctl" && row.argv.indexOf("ring") >= 0);
        if (!actions.length)
          return;
        check(actions.length === 1 && actions[0].argv[4] === "/modules/kdeconnect/devices/phone-b/findmyphone", "selected device action reaches literal endpoint");
        if (!rows().some(row => row.argv.indexOf("shareUrl") >= 0) || !rows().some(row => row.argv.indexOf("sendCommand") >= 0))
          return;
        check(rows().some(row => row.argv[4] === "/modules/kdeconnect/devices/phone-b/share" && row.argv[row.argv.length - 1] === "file://" + caseDir + "/literal ' file.txt"), "delayed file result preserves captured literal device/path");
        check(client.mainDevice.id === "phone-a" && peerClient.mainDevice.id === "phone-b", "selection and shared observations do not replace peer device");
        client.observation.refreshTimer.stop();
        var original = Array.from(client.observation.devices);
        client.observation.devices = original.map(device => Object.assign({}, device, device.id === "phone-b" ? {
                                                                                                                  reachable: false
                                                                                                                } : {}));
        check(peerClient.mainDevice.id === "phone-a", "configured device loss selects existing reachable fallback");
        client.observation.devices = client.observation.devices.map(device => Object.assign({}, device));
        check(peerClient.mainDevice.id === "phone-b" && !peerClient.mainDevice.reachable, "subsequent unchanged snapshot preserves original configured-device fallback policy");
        client.observation.devices = original;
        check(peerClient.mainDevice.id === "phone-b" && peerClient.mainDevice.reachable, "configured device recovery remains context selected");
        phase = 4;
      }
    } else if (phase === 3 && !snapshot.running) {
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                micFilterRegex: "Controlled",
                                                camFilterRegex: "Controlled",
                                                activeColor: "error"
                                              });
      check(!client.micActive && !client.camActive && peerClient.micActive && peerClient.camActive, "distinct selected filters over one raw sample");
      check(JSON.stringify(main.accessHistory) === history, "instance filters leave common historical values/colors unchanged");
      snapshot.command = ["cp", Settings.cacheDir + "privacy-history.json", caseDir + "/history-after.json"];
      snapshot.running = true;
      phase = 31;
    } else if (phase === 31 && !snapshot.running) {
      selected.pluginSettings = Object.assign({}, selected.pluginSettings, {
                                                micFilterRegex: "[",
                                                camFilterRegex: "["
                                              });
      check(client.micActive && client.camActive, "invalid patterns preserve unfiltered admitted observations");
      mic("", true);
      check(client.micActive && client.micApps.length === 0, "anonymous microphone remains active");
      phase = 4;
    } else if (phase === 4) {
      var before = toasts.length, writes = selected.writes;
      pendingToastCount = before;
      if (plugin === "privacy-indicator") {
        var screenNode = {
          properties: {
            "media.class": "Stream/Output/Video",
            "media.name": "screen-capture",
            "application.name": "Controlled Screen"
          }
        };
        main.updateScreenShareState([screenNode], [
                                      {
                                        source: screenNode
                                      }
                                    ]);
        check(client.scrActive && client.scrApps[0] === "Controlled Screen", "actual linked screen classifier reaches selected projection");
      }
      selected.alive = false;
      peer.alive = false;
      shared.alive = false;
      check(client.current === false, "retired projection is immediately noncurrent");
      if (plugin === "kde-connect") {
        client.triggerFindMyPhone();
        check(client.selectDevice("phone-b", selected) === false && selected.writes === writes, "retired device cannot act or publish");
      } else if (plugin === "noctalia-calculator") {
        client.pressButton("7");
        check(main.currentInput === "0", "retired calculator cannot change shared state");
      } else {
        client.notify("mic");
        check(toasts.length === before, "retired context cannot request a common toast");
      }
      phase = 5;
    } else if (phase === 5) {
      if (plugin === "privacy-indicator")
        check(toasts.length === pendingToastCount, "queued notification from retired contexts never reaches common toast consumer");
      check(main._settingsConsumers.size === 0 && bar.settingsConsumer === null && panel.settingsConsumer === null, "retirement removes all selected projections");
      console.log("PROJECTION_LIFECYCLE: PASS " + plugin);
      Qt.exit(0);
    }
  }
  Connections {
    target: Settings
    function onSettingsLoaded() {
      try {
        root.begin();
      } catch (error) {
        console.error(String(error));
        Qt.exit(2);
      }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      try {
        root.drive();
      } catch (error) {
        console.error(String(error) + "\n" + (error.stack || ""));
        Qt.exit(2);
      }
    }
  }
  Component.onCompleted: begin()
}
