pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

Singleton {
  id: root

  // Primary battery device (prioritizes laptop over Bluetooth)
  readonly property var primaryDevice: {
    var laptopBattery = findLaptopBattery();
    if (laptopBattery !== null) {
      return laptopBattery;
    }

    var bluetoothDevice = findBluetoothBatteryDevice();
    if (bluetoothDevice !== null) {
      return bluetoothDevice;
    }

    return null;
  }

  readonly property string primaryBatteryType: {
    if (findLaptopBattery() !== null) {
      return "laptop";
    } else if (findBluetoothBatteryDevice() !== null) {
      return "bluetooth";
    }
    return "none";
  }

  readonly property real batteryPercentage: {
    if (primaryBatteryType === "laptop" && primaryDevice) {
      return (primaryDevice.percentage || 0) * 100;
    } else if (primaryBatteryType === "bluetooth" && primaryDevice) {
      return (primaryDevice.battery || 0) * 100;
    }
    return 0;
  }

  readonly property bool batteryCharging: {
    if (primaryBatteryType === "laptop" && primaryDevice) {
      return primaryDevice.state === UPowerDeviceState.Charging;
    }
    return false;
  }

  readonly property bool batteryReady: {
    if (primaryBatteryType === "laptop" && primaryDevice) {
      return primaryDevice.ready && primaryDevice.percentage !== undefined;
    } else if (primaryBatteryType === "bluetooth" && primaryDevice) {
      return primaryDevice.connected && primaryDevice.batteryAvailable && primaryDevice.battery !== undefined;
    }
    return false;
  }

  readonly property bool batteryPresent: {
    if (primaryBatteryType === "laptop" && primaryDevice) {
      return (primaryDevice.type === UPowerDeviceType.Battery && primaryDevice.isPresent !== undefined) ? primaryDevice.isPresent : (primaryDevice.ready && primaryDevice.percentage !== undefined);
    } else if (primaryBatteryType === "bluetooth" && primaryDevice) {
      return primaryDevice.connected === true;
    }
    return false;
  }

  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "battery-exclamation";
    }

    if (charging) {
      return "common.charging";
    } else {
      if (percent >= 90)
        return "battery-4";
      if (percent >= 50)
        return "battery-3";
      if (percent >= 25)
        return "battery-2";
      if (percent >= 0)
        return "battery-1";
      return "battery";
    }
  }

  function findBluetoothBatteryDevice() {
    if (!BluetoothService.devices) {
      return null;
    }
    var devices = BluetoothService.devices.values || [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.connected && device.batteryAvailable && device.battery !== undefined) {
        return device;
      }
    }
    return null;
  }

  function findLaptopBattery() {
    if (UPower.displayDevice && UPower.displayDevice.isLaptopBattery) {
      return UPower.displayDevice;
    }
    if (!UPower.devices) {
      return null;
    }

    var devices = UPower.devices.values || [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.type === UPowerDeviceType.Battery && device.isLaptopBattery && device.percentage !== undefined) {
        return device;
      }
    }
    return null;
  }

  function hasAnyBattery() {
    var laptopBattery = findLaptopBattery();
    var bluetoothDevice = findBluetoothBatteryDevice();
    return (laptopBattery !== null) || (bluetoothDevice !== null);
  }
}
