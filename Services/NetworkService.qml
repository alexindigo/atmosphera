pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Core properties
  property var networks: ({})
  property string connectingSsid: ""
  property string connectStatus: ""
  property string connectStatusSsid: ""
  property string connectError: ""
  property bool isLoading: false
  property bool ethernet: false
  property int retryCount: 0
  property int maxRetries: 3
  
  // File path for persistent storage
  property string cacheFile: Settings.cacheDir + "network.json"

  // Stable properties for UI
  readonly property alias cache: adapter
  readonly property string lastConnectedNetwork: adapter.lastConnected

  // File-based persistent storage
  FileView {
    id: cacheFileView
    path: root.cacheFile
    onAdapterUpdated: saveTimer.start()
    onLoaded: {
      Logger.log("Network", "Loaded network cache from disk")
      // Try to auto-connect on startup if WiFi is enabled
      if (Settings.data.network.wifiEnabled && adapter.lastConnected) {
        autoConnectTimer.start()
      }
    }
    onLoadFailed: function(error) {
      Logger.log("Network", "No existing cache found, creating new one")
      // Initialize with empty data
      adapter.knownNetworks = ({})
      adapter.lastConnected = ""
    }

    JsonAdapter {
      id: adapter
      property var knownNetworks: ({})
      property string lastConnected: ""
      property int lastRefresh: 0
    }
  }

  // Save timer to batch writes
  Timer {
    id: saveTimer
    running: false
    interval: 1000
    onTriggered: cacheFileView.writeAdapter()
  }

  Component.onCompleted: {
    Logger.log("Network", "Service started")
    
    if (Settings.data.network.wifiEnabled) {
      refreshNetworks()
    }
  }

  // Signal strength icon mapping
  function signalIcon(signal) {
    const levels = [
      { threshold: 80, icon: "network_wifi" },
      { threshold: 60, icon: "network_wifi_3_bar" },
      { threshold: 40, icon: "network_wifi_2_bar" },
      { threshold: 20, icon: "network_wifi_1_bar" }
    ]
    
    for (const level of levels) {
      if (signal >= level.threshold) return level.icon
    }
    return "signal_wifi_0_bar"
  }

  function isSecured(security) {
    return security && security.trim() !== "" && security.trim() !== "--"
  }

  // Enhanced refresh with retry logic
  function refreshNetworks() {
    if (isLoading) return
    
    isLoading = true
    retryCount = 0
    adapter.lastRefresh = Date.now()
    performRefresh()
  }

  function performRefresh() {
    checkEthernet.running = true
    existingNetworkProcess.running = true
  }

  // Retry mechanism for failed operations
  function retryRefresh() {
    if (retryCount < maxRetries) {
      retryCount++
      Logger.log("Network", `Retrying refresh (${retryCount}/${maxRetries})`)
      retryTimer.start()
    } else {
      isLoading = false
      connectError = "Failed to refresh networks after multiple attempts"
    }
  }

  Timer {
    id: retryTimer
    interval: 1000 * retryCount // Progressive backoff
    repeat: false
    onTriggered: performRefresh()
  }

  Timer {
    id: autoConnectTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (adapter.lastConnected && networks[adapter.lastConnected]?.existing) {
        Logger.log("Network", `Auto-connecting to ${adapter.lastConnected}`)
        connectToExisting(adapter.lastConnected)
      }
    }
  }

  // Forget network function
  function forgetNetwork(ssid) {
    Logger.log("Network", `Forgetting network: ${ssid}`)
    
    // Remove from cache
    let known = adapter.knownNetworks
    delete known[ssid]
    adapter.knownNetworks = known
    
    // Clear last connected if it's this network
    if (adapter.lastConnected === ssid) {
      adapter.lastConnected = ""
    }
    
    // Save changes
    saveTimer.restart()
    
    // Remove NetworkManager profile
    forgetProcess.ssid = ssid
    forgetProcess.running = true
  }

  Process {
    id: forgetProcess
    property string ssid: ""
    running: false
    command: ["nmcli", "connection", "delete", "id", ssid]
    
    stdout: StdioCollector {
      onStreamFinished: {
        Logger.log("Network", `Successfully forgot network: ${forgetProcess.ssid}`)
        refreshNetworks()
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.includes("no such connection profile")) {
          Logger.log("Network", `Network profile not found: ${forgetProcess.ssid}`)
        } else {
          Logger.warn("Network", `Error forgetting network: ${text}`)
        }
        refreshNetworks()
      }
    }
  }

  // WiFi enable/disable functions
  function setWifiEnabled(enabled) {
    if (enabled) {
      isLoading = true
      wifiRadioProcess.action = "on"
      wifiRadioProcess.running = true
    } else {
      // Save current connection for later
      for (const ssid in networks) {
        if (networks[ssid].connected) {
          adapter.lastConnected = ssid
          saveTimer.restart()
          disconnectNetwork(ssid)
          break
        }
      }
      
      wifiRadioProcess.action = "off"
      wifiRadioProcess.running = true
    }
  }

  // Unified WiFi radio control
  Process {
    id: wifiRadioProcess
    property string action: "on"
    running: false
    command: ["nmcli", "radio", "wifi", action]
    
    onRunningChanged: {
      if (!running) {
        if (action === "on") {
          wifiEnableTimer.start()
        } else {
          root.networks = ({})
          root.isLoading = false
        }
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.warn("Network", `Error ${action === "on" ? "enabling" : "disabling"} WiFi: ${text}`)
        }
      }
    }
  }

  Timer {
    id: wifiEnableTimer
    interval: 2000
    repeat: false
    onTriggered: {
      refreshNetworks()
      if (adapter.lastConnected) {
        reconnectTimer.start()
      }
    }
  }

  Timer {
    id: reconnectTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (adapter.lastConnected && networks[adapter.lastConnected]?.existing) {
        connectToExisting(adapter.lastConnected)
      }
    }
  }

  // Connection management
  function connectNetwork(ssid, security) {
    connectingSsid = ssid
    connectStatus = ""
    connectStatusSsid = ssid
    connectError = ""
    
    // Check if profile exists
    if (networks[ssid]?.existing) {
      connectToExisting(ssid)
      return
    }
    
    // Check cache for known network
    const known = adapter.knownNetworks[ssid]
    if (known?.profileName) {
      connectToExisting(known.profileName)
      return
    }
    
    // New connection - need password for secured networks
    if (isSecured(security)) {
      // Password will be provided through submitPassword
      return
    }
    
    // Open network - connect directly
    createAndConnect(ssid, "", security)
  }

  function submitPassword(ssid, password) {
    const security = networks[ssid]?.security || ""
    createAndConnect(ssid, password, security)
  }

  function connectToExisting(ssid) {
    connectingSsid = ssid
    upConnectionProcess.profileName = ssid
    upConnectionProcess.running = true
  }

  function createAndConnect(ssid, password, security) {
    connectingSsid = ssid
    
    connectProcess.ssid = ssid
    connectProcess.password = password
    connectProcess.isSecured = isSecured(security)
    connectProcess.running = true
  }

  function disconnectNetwork(ssid) {
    disconnectProcess.ssid = ssid
    disconnectProcess.running = true
  }

  // Connection process
  Process {
    id: connectProcess
    property string ssid: ""
    property string password: ""
    property bool isSecured: false
    running: false
    
    command: {
      const cmd = ["nmcli", "device", "wifi", "connect", ssid]
      if (isSecured && password) {
        cmd.push("password", password)
      }
      return cmd
    }
    
    stdout: StdioCollector {
      onStreamFinished: {
        handleConnectionSuccess(connectProcess.ssid)
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        handleConnectionError(connectProcess.ssid, text)
      }
    }
  }

  Process {
    id: upConnectionProcess
    property string profileName: ""
    running: false
    command: ["nmcli", "connection", "up", "id", profileName]
    
    stdout: StdioCollector {
      onStreamFinished: {
        handleConnectionSuccess(upConnectionProcess.profileName)
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        handleConnectionError(upConnectionProcess.profileName, text)
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
        connectingSsid = ""
        connectStatus = ""
        connectStatusSsid = ""
        connectError = ""
        refreshNetworks()
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.warn("Network", `Disconnect warning: ${text}`)
        }
      }
    }
  }

  // Connection result handlers
  function handleConnectionSuccess(ssid) {
    connectingSsid = ""
    connectStatus = "success"
    connectStatusSsid = ssid
    connectError = ""
    
    // Update cache
    let known = adapter.knownNetworks
    known[ssid] = {
      profileName: ssid,
      lastConnected: Date.now(),
      autoConnect: true
    }
    adapter.knownNetworks = known
    adapter.lastConnected = ssid
    saveTimer.restart()
    
    Logger.log("Network", `Successfully connected to ${ssid}`)
    refreshNetworks()
  }

  function handleConnectionError(ssid, error) {
    connectingSsid = ""
    connectStatus = "error"
    connectStatusSsid = ssid
    connectError = parseError(error)
    
    Logger.warn("Network", `Failed to connect to ${ssid}: ${error}`)
  }

  function parseError(error) {
    // Simplify common error messages
    if (error.includes("Secrets were required") || error.includes("no secrets provided")) {
      return "Incorrect password"
    }
    if (error.includes("No network with SSID")) {
      return "Network not found"
    }
    if (error.includes("Connection activation failed")) {
      return "Connection failed. Please try again."
    }
    if (error.includes("Timeout")) {
      return "Connection timeout. Network may be out of range."
    }
    // Return first line only
    return error.split("\n")[0].trim()
  }

  // Network scanning processes
  Process {
    id: existingNetworkProcess
    running: false
    command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
    
    stdout: StdioCollector {
      onStreamFinished: {
        const profiles = {}
        const lines = text.split("\n").filter(l => l.trim())
        
        for (const line of lines) {
          const [name, type] = line.split(":")
          if (name && type === "802-11-wireless") {
            profiles[name] = { ssid: name, type: type }
          }
        }
        
        scanProcess.existingProfiles = profiles
        scanProcess.running = true
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.warn("Network", "Error listing connections:", text)
          retryRefresh()
        }
      }
    }
  }

  Process {
    id: scanProcess
    property var existingProfiles: ({})
    running: false
    command: ["nmcli", "-t", "-f", "SSID,SECURITY,SIGNAL,IN-USE", "device", "wifi", "list"]
    
    stdout: StdioCollector {
      onStreamFinished: {
        const networksMap = {}
        const lines = text.split("\n").filter(l => l.trim())
        
        for (const line of lines) {
          const parts = line.split(":")
          if (parts.length < 4) continue
          
          const [ssid, security, signalStr, inUse] = parts
          if (!ssid) continue
          
          const signal = parseInt(signalStr) || 0
          const connected = inUse === "*"
          
          // Update last connected if we find the connected network
          if (connected && adapter.lastConnected !== ssid) {
            adapter.lastConnected = ssid
            saveTimer.restart()
          }
          
          // Merge with existing or create new
          if (!networksMap[ssid] || signal > networksMap[ssid].signal) {
            networksMap[ssid] = {
              ssid: ssid,
              security: security || "--",
              signal: signal,
              connected: connected,
              existing: ssid in scanProcess.existingProfiles,
              cached: ssid in adapter.knownNetworks
            }
          }
        }
        
        root.networks = networksMap
        root.isLoading = false
        scanProcess.existingProfiles = {}
        
        Logger.log("Network", `Found ${Object.keys(networksMap).length} networks`)
      }
    }
    
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) {
          Logger.warn("Network", "Error scanning networks:", text)
          retryRefresh()
        }
      }
    }
  }

  Process {
    id: checkEthernet
    running: false
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device"]
    
    stdout: StdioCollector {
      onStreamFinished: {
        root.ethernet = text.split("\n").some(line => {
          const parts = line.split(":")
          return parts[1] === "ethernet" && parts[2] === "connected"
        })
      }
    }
  }

  // Auto-refresh timer
  Timer {
    interval: 30000 // 30 seconds
    running: Settings.data.network.wifiEnabled && !isLoading
    repeat: true
    onTriggered: {
      // Only refresh if we should
      const now = Date.now()
      const timeSinceLastRefresh = now - adapter.lastRefresh
      
      // Refresh if: connected, or it's been more than 30 seconds
      if (hasActiveConnection || timeSinceLastRefresh > 30000) {
        refreshNetworks()
      }
    }
  }

  property bool hasActiveConnection: {
    return Object.values(networks).some(net => net.connected)
  }

  // Menu state management
  function onMenuOpened() {
    if (Settings.data.network.wifiEnabled) {
      refreshNetworks()
    }
  }

  function onMenuClosed() {
    // Clean up temporary states
    connectStatus = ""
    connectError = ""
  }
}