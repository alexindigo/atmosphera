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

  Component.onCompleted: {
    Logger.log("Network", "Service initialized")
    syncWifiState()
    if (Settings.data.network.wifiEnabled) {
      scan()
    }
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

  // Single refresh timer for periodic scans
  Timer {
    id: refreshTimer
    interval: 30000
    running: Settings.data.network.wifiEnabled && !scanning
    repeat: true
    onTriggered: scan()
  }

  // Delayed scan timer for WiFi enable
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

  function scan() {
    if (scanning) return
    
    scanning = true
    lastError = ""
    scanProcess.running = true
  }

  function connect(ssid, password = "") {
    if (connecting) return
    
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
    disconnectProcess.ssid = ssid
    disconnectProcess.running = true
  }

  function forget(ssid) {
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

  // Helper functions
  function signalIcon(signal) {
    if (signal >= 80) return "network_wifi"
    if (signal >= 60) return "network_wifi_3_bar"
    if (signal >= 40) return "network_wifi_2_bar"
    if (signal >= 20) return "network_wifi_1_bar"
    return "signal_wifi_0_bar"
  }

  function isSecured(security) {
    return security && security !== "--" && security.trim() !== ""
  }

  // Processes
  Process {
    id: wifiStateProcess
    running: false
    command: ["nmcli", "radio", "wifi"]
    
    stdout: StdioCollector {
      onStreamFinished: {
        const enabled = text.trim() === "enabled"
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
      # Get existing profiles
      profiles=$(nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless' | cut -d: -f1)
      
      # Get WiFi networks
      nmcli -t -f SSID,SECURITY,SIGNAL,IN-USE device wifi list | while read line; do
        ssid=$(echo "$line" | cut -d: -f1)
        security=$(echo "$line" | cut -d: -f2)
        signal=$(echo "$line" | cut -d: -f3)
        in_use=$(echo "$line" | cut -d: -f4)
        
        # Skip empty SSIDs
        if [ -z "$ssid" ]; then
          continue
        fi
        
        existing=false
        if echo "$profiles" | grep -q "^$ssid$"; then
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
          if (parts.length < 5) continue
          
          const ssid = parts[0]
          if (!ssid || ssid.trim() === "") continue
          
          const network = {
            ssid: ssid,
            security: parts[1] || "--",
            signal: parseInt(parts[2]) || 0,
            connected: parts[3] === "*",
            existing: parts[4] === "true",
            cached: ssid in cacheAdapter.knownNetworks
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
          profileName: connectProcess.ssid,
          lastConnected: Date.now()
        }
        cacheAdapter.knownNetworks = known
        cacheAdapter.lastConnected = connectProcess.ssid
        saveCache()
        
        root.connecting = false
        root.connectingTo = ""
        Logger.log("Network", "Connected to " + connectProcess.ssid)
        
        // Rescan to update status
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
    
    onRunningChanged: {
      if (!running) {
        delayedScanTimer.interval = 1000
        delayedScanTimer.restart()
      }
    }
  }

  Process {
    id: forgetProcess
    property string ssid: ""
    running: false
    command: ["nmcli", "connection", "delete", "id", ssid]
    
    onRunningChanged: {
      if (!running) {
        delayedScanTimer.interval = 1000
        delayedScanTimer.restart()
      }
    }
  }
}