pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  // ============================================================================
  // Properties
  // ============================================================================

  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
  readonly property int state: adapter?.state ?? 0
  readonly property bool available: adapter !== null
  readonly property bool enabled: adapter?.enabled ?? false
  readonly property bool blocked: adapter?.state === BluetoothAdapterState.Blocked
  readonly property bool discovering: adapter?.discovering ?? false
  readonly property var devices: adapter?.devices ?? null

  readonly property var pairedDevices: _filterDevices(dev => dev.paired || dev.trusted)
  readonly property var connectedDevices: _filterDevices(dev => dev.connected)
  readonly property var allDevicesWithBattery: _filterDevices(dev => dev.batteryAvailable && dev.battery > 0)

  // Internal state tracking
  property bool airplaneModeToggled: false
  property bool lastBluetoothBlocked: false
  property var devicesBeingPaired: ({})
  property var connectionAttempts: ({})

  // ============================================================================
  // Initialization
  // ============================================================================

  function init() {
    Logger.i("Bluetooth", "Service started");
    _configureAdapter();
  }

  onAdapterChanged: _configureAdapter()

  // ============================================================================
  // Public API - Device Actions
  // ============================================================================

  function connectDeviceWithTrust(device) {
    if (!device)
      return;

    const deviceName = _getDeviceName(device);
    if (!device.trusted) {
      Logger.i("Bluetooth", "Setting device as trusted:", deviceName);
      device.trusted = true;
    }

    if (!device.paired) {
      Logger.i("Bluetooth", "Pairing device before connection:", deviceName);
      devicesBeingPaired[device.address] = true;
      device.pair();
    } else {
      Qt.callLater(() => {
                     if (device && !device.connected) {
                       Logger.i("Bluetooth", "Connecting to paired device:", deviceName);
                       device.connect();
                     }
                   });
    }
  }

  function disconnectDevice(device) {
    if (device)
      device.disconnect();
  }

  function forgetDevice(device) {
    if (!device)
      return;

    Logger.i("Bluetooth", "Forgetting device:", _getDeviceName(device));
    _cleanupDeviceTracking(device.address);
    device.trusted = false;
    device.forget();
  }

  function forgetAndRepair(device) {
    if (!device)
      return;

    Logger.i("Bluetooth", "Force re-pairing device:", _getDeviceName(device));
    const deviceAddress = device.address;

    delete connectionAttempts[deviceAddress];
    device.trusted = false;
    device.forget();

    Qt.callLater(() => {
                   if (device) {
                     Logger.i("Bluetooth", "Starting fresh pairing for:", _getDeviceName(device));
                     devicesBeingPaired[deviceAddress] = true;
                     device.trusted = true;
                     device.pair();
                   }
                 });
  }

  function setBluetoothEnabled(state) {
    if (!adapter) {
      Logger.w("Bluetooth", "No adapter available");
      return;
    }
    Logger.i("Bluetooth", "SetBluetoothEnabled", state);
    adapter.enabled = state;
  }

  // ============================================================================
  // Public API - Device Info Helpers
  // ============================================================================

  function sortDevices(devices) {
    return devices.sort((a, b) => {
                          const aName = _getDeviceName(a);
                          const bName = _getDeviceName(b);
                          const aHasRealName = aName.includes(" ") && aName.length > 3;
                          const bHasRealName = bName.includes(" ") && bName.length > 3;

                          if (aHasRealName !== bHasRealName)
                          return aHasRealName ? -1 : 1;

                          const aSignal = a.signalStrength > 0 ? a.signalStrength : 0;
                          const bSignal = b.signalStrength > 0 ? b.signalStrength : 0;
                          return bSignal - aSignal;
                        });
  }

  function getDeviceIcon(device) {
    if (!device)
      return "bt-device-generic";

    const name = _getDeviceName(device).toLowerCase();
    const icon = (device.icon || "").toLowerCase();

    const patterns = {
      "bt-device-headphones": ["headset", "audio", "headphone", "airpod", "arctis"],
      "bt-device-mouse": ["mouse"],
      "bt-device-keyboard": ["keyboard"],
      "bt-device-phone": ["phone", "iphone", "android", "samsung"],
      "bt-device-watch": ["watch"],
      "bt-device-speaker": ["speaker"],
      "bt-device-tv": ["display", "tv"]
    };

    for (const [deviceIcon, keywords] of Object.entries(patterns)) {
      if (keywords.some(keyword => icon.includes(keyword) || name.includes(keyword))) {
        return deviceIcon;
      }
    }
    return "bt-device-generic";
  }

  function canConnect(device) {
    return device && !device.connected && !device.pairing && !device.blocked;
  }

  function canDisconnect(device) {
    return device && device.connected && !device.pairing && !device.blocked;
  }

  function isDeviceBusy(device) {
    return device && (device.pairing || device.state === BluetoothDeviceState.Disconnecting || device.state === BluetoothDeviceState.Connecting);
  }

  function getStatusString(device) {
    if (device.state === BluetoothDeviceState.Connecting)
      return "Connecting...";
    if (device.pairing)
      return "Pairing...";
    if (device.blocked)
      return "Blocked";
    return "";
  }

  function getSignalStrength(device) {
    if (!device || !device.signalStrength || device.signalStrength <= 0) {
      return "Signal: Unknown";
    }
    const signal = device.signalStrength;
    const levels = [[80, "Excellent"], [60, "Good"], [40, "Fair"], [20, "Poor"]];
    for (const [threshold, label] of levels) {
      if (signal >= threshold)
        return `Signal: ${label}`;
    }
    return "Signal: Very poor";
  }

  function getSignalIcon(device) {
    if (!device || !device.signalStrength || device.signalStrength <= 0) {
      return "antenna-bars-off";
    }
    const signal = device.signalStrength;
    const icons = [[80, "5"], [60, "4"], [40, "3"], [20, "2"]];
    for (const [threshold, level] of icons) {
      if (signal >= threshold)
        return `antenna-bars-${level}`;
    }
    return "antenna-bars-1";
  }

  function getBattery(device) {
    return `Battery: ${Math.round(device.battery * 100)}%`;
  }

  // ============================================================================
  // Device Monitoring
  // ============================================================================

  Repeater {
    model: root.devices

    Connections {
      target: modelData

      function onPairedChanged() {
        if (!modelData?.paired)
          return;
        _handlePairingSuccess(modelData);
      }

      function onPairingChanged() {
        if (!modelData)
          return;
        _handlePairingCancelled(modelData);
      }

      function onConnectedChanged() {
        if (!modelData)
          return;
        _handleConnectionChanged(modelData);
      }

      function onStateChanged() {
        if (!modelData)
          return;
        _handleStateChanged(modelData);
      }
    }
  }

  // ============================================================================
  // Adapter State Monitoring
  // ============================================================================

  Connections {
    target: adapter

    function onStateChanged() {
      if (!adapter || adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling) {
        return;
      }

      Logger.d("Bluetooth", "Adapter state changed:", adapter.state);
      const bluetoothBlockedToggled = root.blocked !== lastBluetoothBlocked;
      lastBluetoothBlocked = root.blocked;

      if (bluetoothBlockedToggled) {
        checkWifiBlocked.running = true;
      } else if (adapter.state === BluetoothAdapterState.Enabled) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth");
        discoveryTimer.running = true;
      } else if (adapter.state === BluetoothAdapterState.Disabled) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off");
      }
    }
  }

  // ============================================================================
  // Private Helper Functions
  // ============================================================================

  function _filterDevices(filterFn) {
    if (!adapter?.devices)
      return [];
    return adapter.devices.values.filter(dev => dev && filterFn(dev));
  }

  function _getDeviceName(device) {
    return device?.name || device?.deviceName || "Unknown";
  }

  function _cleanupDeviceTracking(address) {
    delete devicesBeingPaired[address];
    delete connectionAttempts[address];
  }

  function _configureAdapter() {
    if (!adapter)
      return;

    Logger.i("Bluetooth", "Configuring adapter...");
    if (!adapter.pairable)
      adapter.pairable = true;
    adapter.pairableTimeout = 0;
  }

  function _handlePairingSuccess(device) {
    const address = device.address;
    if (!devicesBeingPaired[address])
      return;

    Logger.i("Bluetooth", "Device paired successfully, connecting:", _getDeviceName(device));
    delete devicesBeingPaired[address];

    Qt.callLater(() => {
                   if (device?.paired && !device.connected) {
                     Logger.i("Bluetooth", "Auto-connecting after pairing:", _getDeviceName(device));
                     device.connect();
                   }
                 });
  }

  function _handlePairingCancelled(device) {
    const address = device.address;
    if (!device.pairing && devicesBeingPaired[address] && !device.paired) {
      Logger.w("Bluetooth", "Pairing cancelled or failed for:", _getDeviceName(device));
      delete devicesBeingPaired[address];
    }
  }

  function _handleConnectionChanged(device) {
    const name = _getDeviceName(device);
    const address = device.address;

    if (device.connected) {
      Logger.i("Bluetooth", "Device connected:", name);
      delete connectionAttempts[address];
      ToastService.showNotice(I18n.tr("bluetooth.panel.title"), `${name} connected`, "bluetooth-connected");
    } else {
      Logger.i("Bluetooth", "Device disconnected:", name);
    }
  }

  function _handleStateChanged(device) {
    const name = _getDeviceName(device);
    const address = device.address;
    const state = device.state;

    if (state === BluetoothDeviceState.Connecting) {
      Logger.d("Bluetooth", "Device connecting:", name);
      connectionAttempts[address] = {
        name: name,
        startTime: Date.now(),
        wasConnecting: true
      };
    } else if (state === BluetoothDeviceState.Disconnecting) {
      Logger.d("Bluetooth", "Device disconnecting:", name);
    } else if (state === BluetoothDeviceState.Disconnected) {
      _checkFailedConnection(device, address, name);
    }
  }

  function _checkFailedConnection(device, address, name) {
    const attempt = connectionAttempts[address];
    if (!attempt?.wasConnecting || device.connected)
      return;

    const timeSinceAttempt = Date.now() - attempt.startTime;
    if (timeSinceAttempt < 5000) {
      Logger.w("Bluetooth", "Connection failed quickly for:", name, "- likely missing Bluetooth profiles");
      ToastService.showError("Bluetooth Connection Failed", `${name} - Missing audio profiles. Right-click to forget and try re-pairing, or check system Bluetooth services.`, "bluetooth-off");
    }
    delete connectionAttempts[address];
  }

  // ============================================================================
  // Internal Components
  // ============================================================================

  Timer {
    id: discoveryTimer
    interval: 1000
    repeat: false
    onTriggered: adapter.discovering = true
  }

  Process {
    id: checkWifiBlocked
    running: false
    command: ["rfkill", "list", "wifi"]

    stdout: StdioCollector {
      onStreamFinished: {
        const wifiBlocked = text?.trim().includes("Soft blocked: yes") ?? false;
        Logger.d("Network", "Wi-Fi adapter blocked:", wifiBlocked);

        if (wifiBlocked === root.blocked) {
          root.airplaneModeToggled = true;
          NetworkService.setWifiEnabled(!wifiBlocked);
          const mode = wifiBlocked ? "enabled" : "disabled";
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr(`toast.airplane-mode.${mode}`), wifiBlocked ? "plane" : "plane-off");
        } else if (adapter.enabled) {
          ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth");
          discoveryTimer.running = true;
        } else {
          ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off");
        }
        root.airplaneModeToggled = false;
      }
    }
  }
}
