pragma Singleton
import QtQuick
import QtQml

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

Singleton {
  id: root

  readonly property var primaryDevice: _laptopBattery || _bluetoothBattery || null // Primary battery device (prioritizes laptop over Bluetooth)
  readonly property real batteryPercentage: getPercentage(primaryDevice)
  readonly property bool batteryCharging: isCharging(primaryDevice)
  readonly property bool batteryPluggedIn: isPluggedIn(primaryDevice)
  readonly property bool batteryReady: isDeviceReady(primaryDevice)
  readonly property bool batteryPresent: isDevicePresent(primaryDevice)
  readonly property real warningThreshold: Settings.data.systemMonitor.batteryWarningThreshold
  readonly property real criticalThreshold: Settings.data.systemMonitor.batteryCriticalThreshold
  readonly property string batteryIcon: getIcon(batteryPercentage, batteryCharging, batteryPluggedIn, batteryReady)
  readonly property var laptopBatteries: UPower.devices.values.filter(d => d.isLaptopBattery).sort((x, y) => {
                                                                                                     // Force DisplayDevice to the top
                                                                                                     if (x.nativePath.includes("DisplayDevice"))
                                                                                                     return -1;
                                                                                                     if (y.nativePath.includes("DisplayDevice"))
                                                                                                     return 1;

                                                                                                     // Standard string comparison works for BAT0 vs BAT1
                                                                                                     return x.nativePath.localeCompare(y.nativePath, undefined, {
                                                                                                                                         numeric: true
                                                                                                                                       });
                                                                                                   })
  readonly property var bluetoothBatteries: {
    var list = [];
    var btArray = BluetoothService.devices?.values || [];
    for (var i = 0; i < btArray.length; i++) {
      var btd = btArray[i];
      if (btd && btd.connected && btd.batteryAvailable) {
        list.push(btd);
      }
    }
    return list;
  }

  readonly property var _laptopBattery: UPower.displayDevice.isPresent ? UPower.displayDevice : (laptopBatteries.length > 0 ? laptopBatteries[0] : null)
  readonly property var _bluetoothBattery: bluetoothBatteries.length > 0 ? bluetoothBatteries[0] : null

  property var deviceModel: {
    var model = [
      {
        "key": "__default__",
        "name": I18n.tr("bar.battery.device-default")
      }
    ];
    const devices = UPower.devices?.values || [];
    for (let d of devices) {
      if (!d || d.type === UPowerDeviceType.LinePower) {
        continue;
      }
      model.push({
                   key: d.nativePath || "",
                   name: d.model || d.nativePath || I18n.tr("common.unknown")
                 });
    }
    return model;
  }

  function findDevice(nativePath) {
    if (!nativePath || nativePath === "__default__" || nativePath === "DisplayDevice") {
      return _laptopBattery;
    }

    if (!UPower.devices) {
      return null;
    }

    var deviceArray = UPower.devices.values || [];
    for (var i = 0; i < deviceArray.length; i++) {
      var device = deviceArray[i];
      if (device && device.nativePath === nativePath) {
        if (device.type === UPowerDeviceType.LinePower) {
          continue;
        }
        return device;
      }
    }
    return null;
  }

  function isDevicePresent(device) {
    if (!device) {
      return false;
    }

    // Handle Bluetooth devices (identified by having batteryAvailable property)
    if (device.batteryAvailable !== undefined) {
      return device.connected === true;
    }

    // Handle UPower devices
    if (device.type !== undefined) {
      if (device.type === UPowerDeviceType.Battery && device.isPresent !== undefined) {
        return device.isPresent === true;
      }
      // Fallback for non-battery UPower devices or if isPresent is missing
      return device.ready && device.percentage !== undefined;
    }
    return false;
  }

  function isDeviceReady(device) {
    if (!isDevicePresent(device)) {
      return false;
    }
    if (device.batteryAvailable !== undefined) {
      return device.battery !== undefined;
    }
    return device.ready && device.percentage !== undefined;
  }

  function getPercentage(device) {
    if (!device) {
      return -1;
    }
    if (device.batteryAvailable !== undefined) {
      return Math.round((device.battery || 0) * 100);
    }
    return Math.round((device.percentage || 0) * 100);
  }

  function isCharging(device) {
    if (!device || isBluetoothDevice(device)) {
      // Tracking bluetooth devices can charge or not is a loop hole, none of my devices has it, even if it possible?!
      return false;  // Assuming not charging until someone/quickshell brings a way to do pretty unlikely.
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.Charging;
    }
    return false;
  }

  function isPluggedIn(device) {
    if (!device || isBluetoothDevice(device)) {
      // Tracking bluetooth devices can charge or not is a loop hole, none of my devices has it, even if it possible?!
      return false;  // Assuming not charging until someone/quickshell brings a way to do pretty unlikely.
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge;
    }
    return false;
  }

  function isCriticalBattery(device) {
    if (!device || !isDeviceReady(device)) {
      return false;
    }
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= criticalThreshold;
  }

  function isLowBattery(device) {
    if (!device || !isDeviceReady(device)) {
      return false;
    }
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= warningThreshold && getPercentage(device) > criticalThreshold;
  }

  function isBluetoothDevice(device) {
    return device && device.batteryAvailable !== undefined;
  }

  function getDeviceName(device) {
    if (!isDeviceReady(device)) {
      return "";
    }

    if (!isBluetoothDevice(device) && device.isLaptopBattery) {
      // If there is more than one battery explicitly name them
      // Logger.e("BatteryDebug", "Available Battery count: " + laptopBatteries.length); // can be useful for debugging
      if (laptopBatteries.length > 1 && device.nativePath) {
        if (device.nativePath === "DisplayDevice") {
          return "All batteries (combined)"; // TODO: i18n
        }
        var match = device.nativePath.match(/(\d+)$/);
        if (match) {
          // In case of 2 batteries: bat0 => bat1  bat1 => bat2
          return I18n.tr("common.battery") + " " + (parseInt(match[1]) + 1);  // Append numbers
        }
      }
      // Return Battery if there is only one
      return I18n.tr("common.battery");
    }

    if (isBluetoothDevice(device) && device.name) {
      return device.name;
    }

    if (device.model) {
      return device.model;
    }

    return "";
  }

  function getIcon(percent, charging, pluggedIn, isReady) {
    if (!isReady) {
      return "battery-exclamation";
    }
    if (charging) {
      return "battery-charging";
    }
    if (pluggedIn) {
      return "battery-charging-2";
    }

    const icons = [
            {
              threshold: 80,
              icon: "battery-4"
            },
            {
              threshold: 60,
              icon: "battery-3"
            },
            {
              threshold: 40,
              icon: "battery-2"
            },
            {
              threshold: 20,
              icon: "battery-1"
            },
            {
              threshold: 0,
              icon: "battery"
            }
          ];

    const match = icons.find(tier => percent >= tier.threshold);
    return match ? match.icon : "battery-off"; // New fallback icon clearly represent if nothing is true here.
  }

  function getRateText(device) {
    if (!device || device.changeRate === undefined) {
      return "";
    }
    const rate = Math.abs(device.changeRate);
    if (device.timeToFull > 0) {
      return I18n.tr("battery.charging-rate", {
                       "rate": rate.toFixed(2)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.discharging-rate", {
                       "rate": rate.toFixed(2)
                     });
    }
  }

  function getTimeRemainingText(device) {
    if (!isDeviceReady(device)) {
      return I18n.tr("battery.no-battery-detected");
    }
    if (isPluggedIn(device)) {
      return I18n.tr("battery.plugged-in");
    } else if (device.timeToFull > 0) {
      return I18n.tr("battery.time-until-full", {
                       "time": Time.formatVagueHumanReadableDuration(device.timeToFull)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.time-left", {
                       "time": Time.formatVagueHumanReadableDuration(device.timeToEmpty)
                     });
    }
    return I18n.tr("common.idle");
  }

  function checkDevice(device) {
    if (!device || !isDeviceReady(device)) {
      return;
    }

    const percentage = 1 //getPercentage(device);
    const charging = isCharging(device);
    const plugged = isPluggedIn(device);
    const level = "critical"; //isLowBattery(device) ? "low" : isCriticalBattery(device) ? "critical" : "";
    Logger.e("BatteryServiceDebug", "Device: " + device.model + " Percentage: " + percentage + " Charging: " + charging + " Plugged: " + plugged + " Level: " + level);

    if (level) {
      notify(device, level);
    }

  }

  // Formerly known as maybeNotify
  function notify(device, level) {
    var name = getDeviceName(device);
    var titleKey = level === "critical" ? "toast.battery.critical" : "toast.battery.low";
    var descKey = level === "critical" ? "toast.battery.critical-desc" : "toast.battery.low-desc";

    var title = I18n.tr(titleKey);
    var desc = I18n.tr(descKey, {
                         "percent": getPercentage(device)
                       });

    if (device !== _laptopBattery && name) {
      title = title + " " + name;
    }

    // Use a more urgent icon for critical
    var icon = level === "critical" ? "battery-exclamation" : "battery-charging-2";
    ToastService.showNotice(title, desc, icon);
  }

  Instantiator {
    model: laptopBatteries
    delegate: Connections {
      target: modelData
      function onPercentageChanged() {
        Logger.e("BatteryServiceDebug", "Check in progress... (Battery percentage changed)")
        checkDevice(modelData)
      }
      function onStateChanged() {
        Logger.e("BatteryServiceDebug", "Check in progress... (Battery state changed)")
        checkDevice(modelData)
      }
    }
  }

  Instantiator {
    model: bluetoothBatteries
    delegate: Connections {
      target: modelData
      function onPercentageChanged() {
        Logger.e("BatteryServiceDebug", "Check in progress... (Bluetooth battery changed)")
        checkDevice(modelData)
      }
      function onStateChanged() {
        Logger.e("BatteryServiceDebug", "Check in progress... (Bluetooth battery state changed)")
        checkDevice(modelData)
      }
      function onConnected() {
        Logger.e("BatteryServiceDebug", "Check in progress... (Bluetooth battery connected)")
        checkDevice(modelData)
      }
      function onDisconnected() {
        Logger.e("BatteryServiceDebug", "Check in progress... (Bluetooth battery disconnected)")
        checkDevice(modelData)
      }
    }
  }
}