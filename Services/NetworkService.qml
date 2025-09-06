pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Core state
  property var networks: ({})
  property bool scanning: false
  property bool connecting: false
  property string connectingTo: ""
  property string lastError: ""
  property bool ethernetConnected: false
  property string disconnectingFrom: ""
  property string forgettingNetwork: ""

  // Persistent cache
  property string cacheFile: Settings.cacheDir + "network.json"
  readonly property string cachedLastConnected: cacheAdapter.lastConnected
  readonly property var cachedNetworks: cacheAdapter.knownNetworks

  // Cache file handling
  FileView {
    id: cacheFileView
    path: root.cacheFile

    JsonAdapter {
      id: cacheAdapter
      property var knownNetworks: ({})
      property string lastConnected: ""
    }

    onLoadFailed: {
      cacheAdapter.knownNetworks = ({})
      cacheAdapter.lastConnected = ""
    }
  }

  Connections {
    target: Settings.data.network
    function onWifiEnabledChanged() {
      if (Settings.data.network.wifiEnabled) {
        ToastService.showNotice("Wi-Fi", "Enabled")
      } else {
        ToastService.showNotice("Wi-Fi", "Disabled")
      }
    }
  }

  Component.onCompleted: {
    Logger.log("Network", "Service initialized")
    syncWifiState()
    refresh()
  }

  // Save cache with debounce
  Timer {
    id: saveDebounce
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  function saveCache() {
    saveDebounce.restart()
  }

  // Delayed scan timer
  Timer {
    id: delayedScanTimer
    interval: 7000
    onTriggered: scan()
  }

  // Core functions
  function syncWifiState() {
    wifiStateProcess.running = true
  }

  function setWifiEnabled(enabled) {
    Settings.data.network.wifiEnabled = enabled

    wifiToggleProcess.action = enabled ? "on" : "off"
    wifiToggleProcess.running = true
  }

  function refresh() {
    ethernetStateProcess.running = true

    if (Settings.data.network.wifiEnabled) {
      scan()
    }
  }

  function scan() {
    if (scanning)
      return

    scanning = true
    lastError = ""
    scanProcess.running = true
    Logger.log("Network", "Wi-Fi scan in progress...")
  }

  function connect(ssid, password = "") {
    if (connecting)
      return

    connecting = true
    connectingTo = ssid
    lastError = ""

    // Check if we have a saved connection
    if (networks[ssid]?.existing || cachedNetworks[ssid]) {
      connectProcess.mode = "saved"
      connectProcess.ssid = ssid
      connectProcess.password = ""
    } else {
      connectProcess.mode = "new"
      connectProcess.ssid = ssid
      connectProcess.password = password
    }

    connectProcess.running = true
  }

  function disconnect(ssid) {
    disconnectingFrom = ssid
    disconnectProcess.ssid = ssid
    disconnectProcess.running = true
  }

  function forget(ssid) {
    forgettingNetwork = ssid

    // Remove from cache
    let known = cacheAdapter.knownNetworks
    delete known[ssid]
    cacheAdapter.knownNetworks = known

    if (cacheAdapter.lastConnected === ssid) {
      cacheAdapter.lastConnected = ""
    }

    saveCache()

    // Remove from system
    forgetProcess.ssid = ssid
    forgetProcess.running = true
  }

  // Helper function to immediately update network status
  function updateNetworkStatus(ssid, connected) {
    let nets = networks

    // Update all networks connected status
    for (let key in nets) {
      if (nets[key].connected && key !== ssid) {
        nets[key].connected = false
      }
    }

    // Update the target network if it exists
    if (nets[ssid]) {
      nets[ssid].connected = connected
      nets[ssid].existing = true
      nets[ssid].cached = true
    } else if (connected) {
      // Create a temporary entry if network doesn't exist yet
      nets[ssid] = {
        "ssid": ssid,
        "security": "--",
        "signal": 100,
        "connected"// Default to good signal until real scan
        : true,
        "existing": true,
        "cached": true
      }
    }

    // Trigger property change notification
    networks = ({})
    networks = nets
  }

  // Helper functions
  function signalIcon(signal) {
    if (signal >= 80)
      return "network_wifi"
    if (signal >= 60)
      return "network_wifi_3_bar"
    if (signal >= 40)
      return "network_wifi_2_bar"
    if (signal >= 20)
      return "network_wifi_1_bar"
    return "signal_wifi_0_bar"
  }

  function isSecured(security) {
    return security && security !== "--" && security.trim() !== ""
  }

  // Processes
  Process {
    id: ethernetStateProcess
    running: false
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]

    stdout: StdioCollector {
      onStreamFinished: {
        const connected = text.split("\n").some(line => {
                                                  const parts = line.split(":")
                                                  return parts[1] === "ethernet" && parts[2] === "connected"
                                                })
        if (root.ethernetConnected !== connected) {
          root.ethernetConnected = connected
          Logger.log("Network", "Ethernet connected:", root.ethernetConnected)
        }
      }
    }
  }

  Process {
    id: wifiStateProcess
    running: false
    command: ["nmcli", "radio", "wifi"]

    stdout: StdioCollector {
      onStreamFinished: {
        const enabled = text.trim() === "enabled"
        Logger.log("Network", "Wi-Fi enabled:", enabled)
        if (Settings.data.network.wifiEnabled !== enabled) {
          Settings.data.network.wifiEnabled = enabled
        }
      }
    }
  }

  Process {
    id: wifiToggleProcess
    property string action: "on"
    running: false
    command: ["nmcli", "radio", "wifi", action]

    onRunningChanged: {
      if (!running) {
        if (action === "on") {
          // Clear networks immediately and start delayed scan
          root.networks = ({})
          delayedScanTimer.interval = 8000
          delayedScanTimer.restart()
        } else {
          root.networks = ({})
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.warn("Network", "WiFi toggle error: " + text)
        }
      }
    }
  }

  Process {
    id: scanProcess
    running: false
    command: ["sh", "-c", `
      # Get list of saved connection profiles (just the names)
      profiles=$(nmcli -t -f NAME connection show | tr '\n' '|')

      # Get WiFi networks
      nmcli -t -f SSID,SECURITY,SIGNAL,IN-USE device wifi list --rescan yes | while read line; do
      ssid=$(echo "$line" | cut -d: -f1)
      security=$(echo "$line" | cut -d: -f2)
      signal=$(echo "$line" | cut -d: -f3)
      in_use=$(echo "$line" | cut -d: -f4)

      # Skip empty SSIDs
      if [ -z "$ssid" ]; then
      continue
      fi

      # Check if SSID matches any profile name (simple check)
      # This covers most cases where profile name equals or contains the SSID
      existing=false
      if echo "$profiles" | grep -qF "$ssid|"; then
      existing=true
      fi

      echo "$ssid|$security|$signal|$in_use|$existing"
      done
      `]

    stdout: StdioCollector {
      onStreamFinished: {
        const nets = {}
        const lines = text.split("\n").filter(l => l.trim())

        for (const line of lines) {
          const parts = line.split("|")
          if (parts.length < 5)
          continue

          const ssid = parts[0]
          if (!ssid || ssid.trim() === "")
          continue

          const network = {
            "ssid": ssid,
            "security": parts[1] || "--",
            "signal": parseInt(parts[2]) || 0,
            "connected": parts[3] === "*",
            "existing": parts[4] === "true",
            "cached": ssid in cacheAdapter.knownNetworks
          }

          // Track connected network
          if (network.connected && cacheAdapter.lastConnected !== ssid) {
            cacheAdapter.lastConnected = ssid
            saveCache()
          }

          // Keep best signal for duplicate SSIDs
          if (!nets[ssid] || network.signal > nets[ssid].signal) {
            nets[ssid] = network
          }
        }

        // For logging purpose only
        Logger.log("Network", "Wi-Fi scan completed")
        const oldSSIDs = Object.keys(root.networks)
        const newSSIDs = Object.keys(nets)
        const newNetworks = newSSIDs.filter(ssid => !oldSSIDs.includes(ssid))
        const lostNetworks = oldSSIDs.filter(ssid => !newSSIDs.includes(ssid))
        if (newNetworks.length > 0 || lostNetworks.length > 0) {
          if (newNetworks.length > 0) {
            Logger.log("Network", "New Wi-Fi SSID discovered:", newNetworks.join(", "))
          }
          if (lostNetworks.length > 0) {
            Logger.log("Network", "Wi-Fi SSID disappeared:", lostNetworks.join(", "))
          }
          Logger.log("Network", "Total Wi-Fi SSIDs:", Object.keys(nets).length)
        }

        // Assign the results
        root.networks = nets
        root.scanning = false
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.scanning = false
        if (text.trim()) {
          Logger.warn("Network", "Scan error: " + text)
          // If scan fails, set a short retry
          if (Settings.data.network.wifiEnabled) {
            delayedScanTimer.interval = 5000
            delayedScanTimer.restart()
          }
        }
      }
    }
  }

  Process {
    id: connectProcess
    property string mode: "new"
    property string ssid: ""
    property string password: ""
    running: false

    command: {
      if (mode === "saved") {
        return ["nmcli", "connection", "up", "id", ssid]
      } else {
        const cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (password) {
          cmd.push("password", password)
        }
        return cmd
      }
    }

    stdout: StdioCollector {
      onStreamFinished: {
        // Success - update cache
        let known = cacheAdapter.knownNetworks
        known[connectProcess.ssid] = {
          "profileName": connectProcess.ssid,
          "lastConnected": Date.now()
        }
        cacheAdapter.knownNetworks = known
        cacheAdapter.lastConnected = connectProcess.ssid
        saveCache()

        // Immediately update the UI before scanning
        root.updateNetworkStatus(connectProcess.ssid, true)

        root.connecting = false
        root.connectingTo = ""
        Logger.log("Network", `Connected to network: "${connectProcess.ssid}"`)

        // Still do a scan to get accurate signal and security info
        delayedScanTimer.interval = 1000
        delayedScanTimer.restart()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.connecting = false
        root.connectingTo = ""

        if (text.trim()) {
          // Parse common errors
          if (text.includes("Secrets were required") || text.includes("no secrets provided")) {
            root.lastError = "Incorrect password"
            forget(connectProcess.ssid)
          } else if (text.includes("No network with SSID")) {
            root.lastError = "Network not found"
          } else if (text.includes("Timeout")) {
            root.lastError = "Connection timeout"
          } else {
            root.lastError = text.split("\n")[0].trim()
          }

          Logger.warn("Network", "Connect error: " + text)
        }
      }
    }
  }

  Process {
    id: disconnectProcess
    property string ssid: ""
    running: false
    command: ["nmcli", "connection", "down", "id", ssid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.log("Network", `Disconnected from network: "${disconnectProcess.ssid}"`)

        // Immediately update UI on successful disconnect
        root.updateNetworkStatus(disconnectProcess.ssid, false)
        root.disconnectingFrom = ""

        // Do a scan to refresh the list
        delayedScanTimer.interval = 1000
        delayedScanTimer.restart()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.disconnectingFrom = ""
        if (text.trim()) {
          Logger.warn("Network", "Disconnect error: " + text)
        }
        // Still trigger a scan even on error
        delayedScanTimer.interval = 1000
        delayedScanTimer.restart()
      }
    }
  }

  Process {
    id: forgetProcess
    property string ssid: ""
    running: false

    // Try multiple common profile name patterns
    command: ["sh", "-c", `
      ssid="$1"
      deleted=false

      # Try exact SSID match first
      if nmcli connection delete id "$ssid" 2>/dev/null; then
      echo "Deleted profile: $ssid"
      deleted=true
      fi

      # Try "Auto <SSID>" pattern
      if nmcli connection delete id "Auto $ssid" 2>/dev/null; then
      echo "Deleted profile: Auto $ssid"
      deleted=true
      fi

      # Try "<SSID> 1", "<SSID> 2", etc. patterns
      for i in 1 2 3; do
      if nmcli connection delete id "$ssid $i" 2>/dev/null; then
      echo "Deleted profile: $ssid $i"
      deleted=true
      fi
      done

      if [ "$deleted" = "false" ]; then
      echo "No profiles found for SSID: $ssid"
      fi
      `, "--", ssid]

    stdout: StdioCollector {
      onStreamFinished: {
        Logger.log("Network", `Forget network: "${forgetProcess.ssid}"`)
        Logger.log("Network", text.trim().replace(/[\r\n]/g, " "))

        // Update both cached and existing status immediately
        let nets = root.networks
        if (nets[forgetProcess.ssid]) {
          nets[forgetProcess.ssid].cached = false
          nets[forgetProcess.ssid].existing = false
          // Trigger property change
          root.networks = ({})
          root.networks = nets
        }

        root.forgettingNetwork = ""

        // Quick scan to verify the profile is gone
        delayedScanTimer.interval = 500
        delayedScanTimer.restart()
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.forgettingNetwork = ""
        if (text.trim() && !text.includes("No profiles found")) {
          Logger.warn("Network", "Forget error: " + text)
        }
        // Still Trigger a scan even on error
        delayedScanTimer.interval = 500
        delayedScanTimer.restart()
      }
    }
  }
}
