pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons

Singleton {
  id: root

  // Bluetooth state properties
  property bool isEnabled: Settings.data.network.bluetoothEnabled
  property bool isDiscovering: false
  property var connectedDevices: []
  property var pairedDevices: []
  property var availableDevices: []
  property string lastConnectedDevice: ""
  property string connectStatus: ""
  property string connectStatusDevice: ""
  property string connectError: ""

  // Timer for refreshing device lists
  property Timer refreshTimer: Timer {
    interval: 5000 // Refresh every 5 seconds when discovery is active
    repeat: true
    running: root.isEnabled && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering
    onTriggered: root.refreshDevices()
  }

  Component.onCompleted: {
    Logger.log("Bluetooth", "Service started")

    if (isEnabled && Bluetooth.defaultAdapter) {
      // Ensure adapter is enabled
      if (!Bluetooth.defaultAdapter.enabled) {
        Bluetooth.defaultAdapter.enabled = true
      }

      // Start discovery to find devices
      if (!Bluetooth.defaultAdapter.discovering) {
        Bluetooth.defaultAdapter.discovering = true
      }

      // Refresh devices after a short delay to allow discovery to start
      Qt.callLater(function () {
        refreshDevices()
      })
    }
  }

  // Function to enable/disable Bluetooth
  function setBluetoothEnabled(enabled) {

    if (enabled) {
      // Store the currently connected devices before enabling
      for (const device of connectedDevices) {
        if (device.connected) {
          lastConnectedDevice = device.name || device.deviceName
          break
        }
      }

      // Enable Bluetooth
      if (Bluetooth.defaultAdapter) {
        Bluetooth.defaultAdapter.enabled = true

        // Start discovery to find devices
        if (!Bluetooth.defaultAdapter.discovering) {
          Bluetooth.defaultAdapter.discovering = true
        }

        // Refresh devices after enabling
        Qt.callLater(refreshDevices)
      } else {
        Logger.warn("Bluetooth", "No adapter found")
      }
    } else {
      // Disconnect from current devices before disabling
      for (const device of connectedDevices) {
        if (device.connected) {
          device.disconnect()
        }
      }

      // Disable Bluetooth
      if (Bluetooth.defaultAdapter) {
        Logger.log("Bluetooth", "Disabling adapter")
        Bluetooth.defaultAdapter.enabled = false
      }
    }

    Settings.data.network.bluetoothEnabled = enabled
    isEnabled = enabled
  }

  // Function to refresh device lists
  function refreshDevices() {
    if (!isEnabled || !Bluetooth.defaultAdapter) {
      connectedDevices = []
      pairedDevices = []
      availableDevices = []
      return
    }

    Logger.log("Bluetooth", "refreshDevices")

    // Remove duplicate check since we already did it above
    const connected = []
    const paired = []
    const available = []

    let devices = null

    // Try adapter devices first
    if (Bluetooth.defaultAdapter.enabled && Bluetooth.defaultAdapter.devices) {
      devices = Bluetooth.defaultAdapter.devices
    }

    // Fallback to global devices list
    if (!devices && Bluetooth.devices) {
      devices = Bluetooth.devices
    }

    if (!devices) {
      connectedDevices = []
      pairedDevices = []
      availableDevices = []
      return
    }

    // Use Qt model methods to iterate through the ObjectModel
    let deviceFound = false

    try {
      // Get the row count using the Qt model method
      const rowCount = devices.rowCount()

      if (rowCount > 0) {
        // Iterate through each row using the Qt model data() method
        for (var i = 0; i < rowCount; i++) {
          try {
            // Create a model index for this row
            const modelIndex = devices.index(i, 0)
            if (!modelIndex.valid)
              continue

            // Get the device object using the Qt.UserRole (typically 256)
            const device = devices.data(modelIndex, 256) // Qt.UserRole
            if (!device) {
              // Try alternative role values
              const deviceAlt = devices.data(modelIndex, 0) // Qt.DisplayRole
              if (deviceAlt) {
                device = deviceAlt
              } else {
                continue
              }
            }

            deviceFound = true

            if (device.connected) {
              connected.push(device)
            } else if (device.paired) {
              paired.push(device)
            } else {
              available.push(device)
            }
          } catch (e) {

            // Silent error handling
          }
        }
      }

      // Alternative method: try the values property if available
      if (!deviceFound && devices.values) {
        try {
          const values = devices.values
          if (values && typeof values === 'object') {
            // Try to iterate through values if it's iterable
            if (values.length !== undefined) {
              for (var i = 0; i < values.length; i++) {
                const device = values[i]
                if (device) {
                  deviceFound = true
                  if (device.connected) {
                    connected.push(device)
                  } else if (device.paired) {
                    paired.push(device)
                  } else {
                    available.push(device)
                  }
                }
              }
            }
          }
        } catch (e) {

          // Silent error handling
        }
      }
    } catch (e) {
      Logger.warn("Bluetooth", "Error accessing device model:", e)
    }

    if (!deviceFound) {
      Logger.log("Bluetooth", "No device found")
    }

    connectedDevices = connected
    pairedDevices = paired
    availableDevices = available
  }

  // Function to start discovery
  function startDiscovery() {
    if (!isEnabled || !Bluetooth.defaultAdapter)
      return

    isDiscovering = true
    Bluetooth.defaultAdapter.discovering = true
  }

  // Function to stop discovery
  function stopDiscovery() {
    if (!Bluetooth.defaultAdapter)
      return

    isDiscovering = false
    Bluetooth.defaultAdapter.discovering = false
  }

  // Function to connect to a device
  function connectDevice(device) {
    if (!device)
      return

    // Check if device is still valid (not stale from previous session)
    if (!device.connect || typeof device.connect !== 'function') {
      Logger.warn("Bluetooth", "Device object is stale, refreshing devices")
      refreshDevices()
      return
    }

    connectStatus = "connecting"
    connectStatusDevice = device.name || device.deviceName
    connectError = ""

    try {
      device.connect()
    } catch (error) {
      Logger.error("Bluetooth", "Error connecting to device:", error)
      connectStatus = "error"
      connectError = error.toString()
      Qt.callLater(refreshDevices)
    }
  }

  // Function to disconnect from a device
  function disconnectDevice(device) {
    if (!device)
      return

    // Check if device is still valid (not stale from previous session)
    if (!device.disconnect || typeof device.disconnect !== 'function') {
      Logger.warn("Bluetooth", "Device object is stale, refreshing devices")
      refreshDevices()
      return
    }

    try {
      device.disconnect()
      // Clear connection status
      connectStatus = ""
      connectStatusDevice = ""
      connectError = ""
    } catch (error) {
      Logger.warn("Bluetooth", "Error disconnecting device:", error)
      Qt.callLater(refreshDevices)
    }
  }

  // Function to pair with a device
  function pairDevice(device) {
    if (!device)
      return

    // Check if device is still valid (not stale from previous session)
    if (!device.pair || typeof device.pair !== 'function') {
      Logger.warn("Bluetooth", "Device object is stale, refreshing devices")
      refreshDevices()
      return
    }

    try {
      device.pair()
    } catch (error) {
      Logger.warn("Bluetooth", "Error pairing device:", error)
      Qt.callLater(refreshDevices)
    }
  }

  // Function to forget a device
  function forgetDevice(device) {
    if (!device)
      return

    // Check if device is still valid (not stale from previous session)
    if (!device.forget || typeof device.forget !== 'function') {
      Logger.warn("Bluetooth", "Device object is stale, refreshing devices")
      refreshDevices()
      return
    }

    // Store device info before forgetting (in case device object becomes invalid)
    const deviceName = device.name || device.deviceName || "Unknown Device"

    try {
      device.forget()

      // Clear any connection status that might be related to this device
      if (connectStatusDevice === deviceName) {
        connectStatus = ""
        connectStatusDevice = ""
        connectError = ""
      }

      // Refresh devices after a delay to ensure the forget operation is complete
      Qt.callLater(refreshDevices, 1000)
    } catch (error) {
      Logger.warn("Bluetooth", "Error forgetting device:", error)
      Qt.callLater(refreshDevices, 500)
    }
  }

  // Function to get device icon
  function getDeviceIcon(device) {
    if (!device)
      return "bluetooth"

    // Use device icon if available, otherwise fall back to device type
    if (device.icon) {
      return device.icon
    }

    // Fallback icons based on common device types
    const name = (device.name || device.deviceName || "").toLowerCase()
    if (name.includes("headphone") || name.includes("earbud") || name.includes("airpods")) {
      return "headphones"
    } else if (name.includes("speaker")) {
      return "speaker"
    } else if (name.includes("keyboard")) {
      return "keyboard"
    } else if (name.includes("mouse")) {
      return "mouse"
    } else if (name.includes("phone") || name.includes("mobile")) {
      return "smartphone"
    } else if (name.includes("laptop") || name.includes("computer")) {
      return "laptop"
    }

    return "bluetooth"
  }

  // Function to get device status text
  function getDeviceStatus(device) {
    if (!device)
      return ""

    if (device.connected) {
      return "Connected"
    } else if (device.pairing) {
      return "Pairing..."
    } else if (device.paired) {
      return "Paired"
    } else {
      return "Available"
    }
  }

  // Function to get battery level text
  function getBatteryText(device) {
    if (!device || !device.batteryAvailable)
      return ""

    const percentage = Math.round(device.battery * 100)
    return `${percentage}%`
  }

  // Watch for Bluetooth adapter changes
  Connections {
    target: Bluetooth.defaultAdapter
    ignoreUnknownSignals: true

    function onEnabledChanged() {
      root.isEnabled = Bluetooth.defaultAdapter.enabled
      Settings.data.network.bluetoothEnabled = root.isEnabled
      if (root.isEnabled) {
        Qt.callLater(refreshDevices)
      } else {
        connectedDevices = []
        pairedDevices = []
        availableDevices = []
      }
    }

    function onDiscoveringChanged() {
      root.isDiscovering = Bluetooth.defaultAdapter.discovering
      if (Bluetooth.defaultAdapter.discovering) {
        Qt.callLater(refreshDevices)
      }
    }

    function onStateChanged() {
      if (Bluetooth.defaultAdapter.state >= 4) {
        Qt.callLater(refreshDevices)
      }
    }

    function onDevicesChanged() {
      Qt.callLater(refreshDevices)
    }
  }

  // Watch for global device changes
  Connections {
    target: Bluetooth
    ignoreUnknownSignals: true

    function onDevicesChanged() {
      Qt.callLater(refreshDevices)
    }
  }
}
