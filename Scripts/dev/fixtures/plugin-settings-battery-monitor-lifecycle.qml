// Actual UPower service, Main and children with controlled device/CLI peers.
import QtQuick
import Quickshell
import Quickshell.Io
import "Services/Plugins/PluginSettingsRead.js" as Read
import qs.Commons
import qs.Services.Hardware

ShellRoot {
  id: root
  readonly property string caseDir: Quickshell.env("PHA_BATTERY_CASE")
  property var data: null
  property var main: null
  property var api: null
  property var baseApi: null
  property var client: null
  property var baseClient: null
  property var bar: null
  property var panel: null
  property var oldObserver: null
  property bool oldProcessRetired: false
  property bool baseHoldReady: false
  property bool lastProcessRetired: false
  property int phase: 0
  property double started: Date.now()
  FileView {
    id: input
    path: root.caseDir + "/input.json"
    blockLoading: true
  }
  FileView {
    id: held
    path: root.caseDir + "/held"
    blockLoading: true
  }
  FileView {
    id: baseHeld
    path: root.caseDir + "/base-held"
    blockLoading: true
  }
  Process {
    id: release
    command: ["touch", root.caseDir + "/release"]
  }
  Process {
    id: retirementProbe
    command: ["python3", root.caseDir + "/bin/retirement-probe"]
    onExited: function (code) {
      if (code === 0)
        root.oldProcessRetired = true;
    }
  }
  Process {
    id: holdBase
    command: ["touch", root.caseDir + "/hold-base"]
    onExited: function (code) {
      if (code === 0)
        root.baseHoldReady = true;
    }
  }
  Process {
    id: lastRetirementProbe
    command: ["python3", root.caseDir + "/bin/retirement-probe", "base"]
    onExited: function (code) {
      if (code === 0)
        root.lastProcessRetired = true;
    }
  }
  Component {
    id: apiFactory
    QtObject {
      id: selected
      property var manifest: root.data.manifest
      property string pluginDir: root.data.directory
      required property var pluginSettings
      property var mainInstance: root.main
      property bool alive: true
      property var lifetime: ({
                                alive: true
                              })
      Component.onDestruction: lifetime.alive = false
      readonly property var settingsContext: Read.context(lifetime, function () {
        return selected.pluginSettings;
      }, function () {
        return selected.alive;
      })
      function tr(key, params) {
        return key;
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
      throw new Error("BATTERY_MONITOR_ASSERT: " + phase + ": " + message);
  }
  function create(file, properties) {
    var component = Qt.createComponent("file://" + data.directory + "/" + file);
    check(component.status === Component.Ready, component.errorString());
    var item = component.createObject(content, properties);
    check(item, "actual " + file + " constructs");
    return item;
  }
  function find(object, text) {
    if (object?.text === text)
      return true;
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list)
        if (find(child, text))
          return true;
    }
    return false;
  }
  Timer {
    interval: 60
    running: true
    repeat: true
    onTriggered: {
      try {
        check(Date.now() - root.started < 18000, "finite lifecycle deadline");
        if (root.phase === 0 && Settings.isLoaded && BatteryService.laptopBatteries.length === 3) {
          input.waitForJob();
          root.data = JSON.parse(input.text());
          root.baseApi = apiFactory.createObject(root, {
                                                   pluginSettings: {
                                                     deviceNativePath: "BAT0",
                                                     refreshIntervalSeconds: 60
                                                   }
                                                 });
          root.api = apiFactory.createObject(root, {
                                               pluginSettings: {
                                                 deviceNativePath: "BAT1",
                                                 refreshIntervalSeconds: 60
                                               }
                                             });
          root.main = root.create("Main.qml", {
                                    pluginApi: root.baseApi
                                  });
          root.baseClient = root.main.settingsConsumerFor(root.baseApi.settingsContext);
          root.client = root.main.settingsConsumerFor(root.api.settingsContext);
          root.bar = root.create("BarWidget.qml", {
                                   pluginApi: root.api,
                                   screen: Quickshell.screens[0]
                                 });
          root.panel = root.create("Panel.qml", {
                                     pluginApi: root.api,
                                     width: 700,
                                     height: 750
                                   });
          root.phase = 1;
        } else if (root.phase === 1) {
          if (!root.client.observation || root.client.observation.refreshNonce === 0)
            return;
          check(!root.client.observation.sysfsOk, "malformed helper falls back to real selected UPower device");
          check(root.panel.selectedDevice.nativePath === "BAT1" && root.bar.selectedDevice.nativePath === "BAT1", "both actual views select BAT1");
          check(root.panel.formatPower(root.panel.selectedDevice, false, true) === "common.unavailable" && root.bar.formatPower(true, false) === "", "explicit BAT1 never borrows BAT0 power");
          check(root.panel.formatRemainingTime(root.panel.selectedDevice, true) === "common.unavailable" && root.bar.formatRemainingTime() === "", "explicit BAT1 never borrows BAT0 time");
          check(root.panel.healthText(root.panel.selectedDevice) === "common.unavailable", "explicit BAT1 never borrows BAT0 health");
          check(!JSON.stringify(root.bar.tooltipContent).includes("91%") && !find(root.panel, "17.0 W") && !find(root.bar, "17.0W"), "rendered selected children and tooltip do not display foreign metrics");
          root.api.pluginSettings = {
            deviceNativePath: "missing",
            refreshIntervalSeconds: 60
          };
          root.phase = 2;
        } else if (root.phase === 2) {
          if (!root.client.observation || root.client.observation.refreshNonce === 0)
            return;
          check(root.panel.selectedDevice === null && root.bar.selectedDevice === null, "missing explicit selection never substitutes primaryDevice");
          check(root.panel.statusText(root.panel.selectedDevice) === "status.noBattery" && find(root.panel, "status.noBattery"), "missing source renders no battery");
          root.api.pluginSettings = {
            deviceNativePath: "__default__",
            refreshIntervalSeconds: 60
          };
          root.phase = 3;
        } else if (root.phase === 3) {
          if (!root.client.observation || root.client.observation.refreshNonce === 0)
            return;
          check(root.panel.formatPower(root.panel.selectedDevice, false, true) === "17.0 W" && root.bar.formatPower(true, false) === "17.0W", "default aggregate preserves physical power fallback");
          check(root.panel.healthText(root.panel.selectedDevice) === "91%" && root.panel.formatRemainingTime(root.panel.selectedDevice, true) === "1h", "default aggregate preserves health/time fallbacks");
          check(find(root.panel, "17.0 W") && find(root.panel, "91%"), "actual default Panel renders aggregate metrics");
          root.api.pluginSettings = {
            deviceNativePath: "held-battery",
            refreshIntervalSeconds: 60
          };
          root.oldObserver = root.client.observation;
          root.phase = 4;
        } else if (root.phase === 4) {
          held.reload();
          held.waitForJob();
          if (!held.text())
            return;
          root.api.pluginSettings = {
            deviceNativePath: "BAT0",
            refreshIntervalSeconds: 60
          };
          check(root.client.observation === root.baseClient.observation, "same configured device shares physical observer");
          root.phase = 5;
        } else if (root.phase === 5) {
          if (!root.oldProcessRetired) {
            if (!retirementProbe.running)
              retirementProbe.running = true;
            return;
          }
          if (!root.client.observation.sysfsOk)
            return;
          check(!root.main._observations.has("held-battery") && root.client.observation.sysfsPowerWatts === 11.1, "held old result cannot publish into replacement device");
          release.running = true;
          root.api.alive = false;
          check(root.main._observations.has("BAT0") && root.baseClient.observation.sysfsOk, "one context retirement preserves another same-device lease");
          holdBase.running = true;
          root.phase = 6;
        } else if (root.phase === 6) {
          if (!root.baseHoldReady)
            return;
          root.baseClient.refresh();
          root.phase = 7;
        } else if (root.phase === 7) {
          baseHeld.reload();
          baseHeld.waitForJob();
          if (!baseHeld.text())
            return;
          root.baseApi.alive = false;
          root.phase = 8;
        } else if (root.phase === 8) {
          if (!root.lastProcessRetired) {
            if (!lastRetirementProbe.running)
              lastRetirementProbe.running = true;
            return;
          }
          check(root.main._observations.size === 0 && root.main._settingsConsumers.size === 0, "last context retires all physical observation owners");
          console.log("BATTERY_MONITOR_LIFECYCLE: PASS");
          Qt.exit(0);
        }
      } catch (error) {
        console.error(String(error) + "\n" + (error.stack || ""));
        Qt.exit(2);
      }
    }
  }
}
