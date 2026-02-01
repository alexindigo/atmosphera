pragma Singleton
import QtQuick

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

Singleton {
  id: root

  // Primary battery device (prioritizes laptop over Bluetooth)
  readonly property var primaryDevice: _laptopBattery || _bluetoothBattery || null
  // Whether the primary device is a laptop battery
  readonly property bool isLaptopBattery: _laptopBattery !== null && primaryDevice === _laptopBattery
  readonly property real batteryPercentage: getPercentage(primaryDevice)
  readonly property bool batteryCharging: isCharging(primaryDevice)
  readonly property bool batteryPluggedIn: isPluggedIn(primaryDevice)
  readonly property bool batteryReady: isDeviceReady(primaryDevice)
  readonly property bool batteryPresent: isDevicePresent(primaryDevice)
  readonly property string batteryIcon: getIcon(batteryPercentage, batteryCharging, batteryPluggedIn, batteryReady)

  readonly property var laptopBatteries: UPower.devices.values.filter(d => d.isLaptopBattery)
  readonly property var bluetoothBatteries: {
    var list = [];
    var btArray = BluetoothService.devices?.values || [];
    for (var i = 0; i < btArray.length; i++) {
      var btd = btArray[i];
      if (btd && btd.connected && btd.batteryAvailable) {
        list.push(btd);
      }
    }
    return list
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

  function isBluetoothDevice(device) {
    return device && device.batteryAvailable !== undefined;
  }

  function getDeviceName(device) {
    if (!isDeviceReady(device)) {
      return "";
    }

    // Don't show name for laptop batteries
    if (!isBluetoothDevice(device) && device.isLaptopBattery) {
      // If there is more than one battery explicitly name them
      // Logger.e("BatteryDebug", "Available Battery count: " + laptopBatteries.length); // can be useful for debugging
      if (laptopBatteries.length > 1 && device.nativePath) {
        // In case of 2 batteries: bat0 => bat1  bat1 => bat2
        return I18n.tr("common.battery") + " " + (parseInt(device.nativePath.substring(3)) + 1);
      }
      // If only one battery no numbers needed.
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
    if (percent >= 80) {
      return "battery-4";
    }
    if (percent >= 60) {
      return "battery-3";
    }
    if (percent >= 40) {
      return "battery-2";
    }
    if (percent >= 20) {
      return "battery-1";
    }
    if (percent >= 0) {
      return "battery";
    }
    return "battery-off"; // New fallback icon clearly represent if nothing is true here.
  }

  function getRateText(device) {
    if (!device || device.changeRate === undefined) {
      return "";
    }
    const rate = Math.abs(device.changeRate);
    if (isPluggedIn(device)) {
      return I18n.tr("battery.plugged-in");
    } else if (device.timeToFull > 0) {
      return I18n.tr("battery.charging-rate", {
                       "rate": rate.toFixed(2)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.discharging-rate", {
                       "rate": rate.toFixed(2)
                     });
    }
    return I18n.tr("common.idle");
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
}
