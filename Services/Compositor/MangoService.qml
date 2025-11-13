import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  // Properties that match the facade interface
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  // Signals that match the facade interface
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // Mango-specific properties
  property bool initialized: false
  property bool overviewActive: false
  property var tagCache: ({})
  property var windowCache: ({})
  property var monitorCache: ({})
  property string currentLayout: ""
  property string currentKeyboardLayout: ""

  // Debounce timer for updates
  Timer {
    id: updateTimer
    interval: 50
    repeat: false
    onTriggered: safeUpdate()
  }

  // Initialization
  function initialize() {
    if (initialized)
      return

    try {
      // Initial data fetch
      updateWorkspaces()
      updateWindows()
      queryDisplayScales()
      queryKeyboardLayout()
      
      // Start event watching
      mangoEventStream.running = true
      
      initialized = true
      Logger.i("MangoService", "Service started")
    } catch (e) {
      Logger.e("MangoService", "Failed to initialize:", e)
    }
  }

  // Update workspaces (tags in MangoWC)
  function updateWorkspaces() {
    mangoTagsProcess.running = true
  }

  // Update windows
  function updateWindows() {
    mangoWindowsProcess.running = true
  }

  // Query display scales
  function queryDisplayScales() {
    mangoOutputsProcess.running = true
  }

  // Query keyboard layout
  function queryKeyboardLayout() {
    mangoKeyboardProcess.running = true
  }

  // Mango outputs process for display scale detection
  Process {
    id: mangoOutputsProcess
    running: false
    command: ["mmsg", "-g", "-A"]

    stdout: SplitParser {
      onRead: function (line) {
        try {
          const parts = line.trim().split(/\s+/)
          if (parts.length >= 3 && parts[1] === "scale_factor") {
            const outputName = parts[0]
            const scaleFactor = parseFloat(parts[2])
            
            if (!monitorCache[outputName]) {
              monitorCache[outputName] = {}
            }
            
            monitorCache[outputName].scale = scaleFactor
            monitorCache[outputName].name = outputName
          }
        } catch (e) {
          Logger.e("MangoService", "Failed to parse output scale:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Failed to query outputs, exit code:", exitCode)
        return
      }

      // Convert to expected format and notify
      const scales = {}
      for (const [outputName, data] of Object.entries(monitorCache)) {
        scales[outputName] = {
          "name": data.name,
          "scale": data.scale || 1.0,
          "width": data.width || 0,
          "height": data.height || 0,
          "refresh_rate": data.refresh_rate || 0,
          "x": data.x || 0,
          "y": data.y || 0,
          "active": data.active || false,
          "focused": data.focused || false
        }
      }

      // Notify CompositorService
      if (CompositorService && CompositorService.onDisplayScalesUpdated) {
        CompositorService.onDisplayScalesUpdated(scales)
      }
    }
  }

  // Mango tags process (workspaces)
  Process {
    id: mangoTagsProcess
    running: false
    command: ["mmsg", "-g", "-t"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        mangoTagsProcess.accumulatedOutput += line + "\n"
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Failed to query tags, exit code:", exitCode)
        accumulatedOutput = ""
        return
      }

      try {
        parseTagsData(accumulatedOutput)
      } catch (e) {
        Logger.e("MangoService", "Failed to parse tags:", e)
      } finally {
        accumulatedOutput = ""
      }
    }
  }

  // Mango windows process
  Process {
    id: mangoWindowsProcess
    running: false
    command: ["mmsg", "-g", "-c"]

    property string accumulatedOutput: ""
    property var currentWindow: ({})

    onRunningChanged: {
      if (running) {
        currentWindow = {}
      }
    }

    stdout: SplitParser {
      onRead: function (line) {
        const trimmed = line.trim()
        if (!trimmed) return

        // Format: output property value
        // Example: eDP-1 title joyous-triceratops | ~/.config/quickshell> y
        // Example: eDP-1 appid com.mitchellh.ghostty
        const firstSpace = trimmed.indexOf(' ')
        if (firstSpace === -1) return
        
        const outputName = trimmed.substring(0, firstSpace)
        const rest = trimmed.substring(firstSpace + 1).trim()
        
        const secondSpace = rest.indexOf(' ')
        if (secondSpace === -1) return
        
        const property = rest.substring(0, secondSpace)
        const value = rest.substring(secondSpace + 1).trim()



        if (!mangoWindowsProcess.currentWindow[outputName]) {
          mangoWindowsProcess.currentWindow[outputName] = {}
        }

        if (property === "title") {
          mangoWindowsProcess.currentWindow[outputName].title = value
        } else if (property === "appid") {
          mangoWindowsProcess.currentWindow[outputName].appId = value
        } else if (property === "fullscreen") {
          mangoWindowsProcess.currentWindow[outputName].isFullscreen = value === "1"
        } else if (property === "floating") {
          mangoWindowsProcess.currentWindow[outputName].isFloating = value === "1"
        } else if (property === "x") {
          mangoWindowsProcess.currentWindow[outputName].x = parseInt(value)
        } else if (property === "y") {
          mangoWindowsProcess.currentWindow[outputName].y = parseInt(value)
        } else if (property === "width") {
          mangoWindowsProcess.currentWindow[outputName].width = parseInt(value)
        } else if (property === "height") {
          mangoWindowsProcess.currentWindow[outputName].height = parseInt(value)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Failed to query windows, exit code:", exitCode)
        accumulatedOutput = ""
        currentWindow = {}
        return
      }

      try {
        parseWindowsData(currentWindow)
      } catch (e) {
        Logger.e("MangoService", "Failed to parse windows:", e)
      } finally {
        currentWindow = {}
      }
    }
  }

  // Mango keyboard layout process
  Process {
    id: mangoKeyboardProcess
    running: false
    command: ["mmsg", "-g", "-k"]

    stdout: SplitParser {
      onRead: function (line) {
        try {
          const parts = line.trim().split(/\s+/)
          if (parts.length >= 2 && parts[1] === "kb_layout") {
            const layoutName = parts.slice(2).join(' ')
            if (layoutName && layoutName !== currentKeyboardLayout) {
              currentKeyboardLayout = layoutName
              KeyboardLayoutService.setCurrentLayout(layoutName)
  
            }
          }
        } catch (e) {
          Logger.e("MangoService", "Failed to parse keyboard layout:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Failed to query keyboard layout, exit code:", exitCode)
      }
    }
  }



  // Mango event stream process
  Process {
    id: mangoEventStream
    running: false
    command: ["mmsg", "-w"]

    stdout: SplitParser {
      onRead: function (line) {
        try {
          handleEvent(line.trim())
        } catch (e) {
          Logger.e("MangoService", "Error parsing event:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Event stream exited, exit code:", exitCode)
        // Restart event stream after a delay
        restartTimer.start()
      }
    }
  }

  // Timer to restart event stream
  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: {
      if (initialized) {
        mangoEventStream.running = true
      }
    }
  }

  // Parse tags data and convert to workspace format
  function parseTagsData(output) {
    const lines = output.trim().split('\n')
    const workspacesList = []
    const outputTags = {}
    tagCache = {}

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) continue

      // Parse tag information
      // Format: output tag <tag_num> <state> <clients> <focused>
      // Example: eDP-1 tag 1 1 2 1
      const tagMatch = trimmed.match(/^(\S+)\s+tag\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/)
      if (tagMatch) {
        const [, outputName, tagNum, state, clients, focused] = tagMatch
        const tagId = parseInt(tagNum)
        
        // Store tag info per output
        if (!outputTags[outputName]) {
          outputTags[outputName] = []
        }

        // Convert MangoWC tag state to workspace properties
        // Based on dwl-ipc protocol: bit 0=active, bit 1=urgent, bit 2=occupied
        const isActive = (parseInt(state) & 1) !== 0
        const isUrgent = (parseInt(state) & 2) !== 0  // Note: might be bit 1 for urgent
        const isOccupied = parseInt(clients) > 0

        const workspaceData = {
          "id": tagId,
          "idx": tagId,
          "name": tagId.toString(),
          "output": outputName,
          "isActive": isActive,
          "isFocused": isActive && parseInt(focused) === 1,
          "isUrgent": isUrgent,
          "isOccupied": isOccupied
        }

        tagCache[tagId] = workspaceData
        outputTags[outputName].push(workspaceData)

      }

      // Parse layout information
      // Format: output layout <layout_name>
      const layoutMatch = trimmed.match(/^(\S+)\s+layout\s+(\S+)$/)
      if (layoutMatch) {
        const [, outputName, layoutName] = layoutMatch
        currentLayout = layoutName
        
        // Detect overview state - MangoWC uses "󰃇" symbol for overview
        const wasOverviewActive = overviewActive
        overviewActive = (layoutName === "󰃇")
        
        // Emit signal if overview state changed
        if (wasOverviewActive !== overviewActive) {
          Logger.d("MangoService", `Overview state changed: ${overviewActive}`)
        }
      }

      // Parse clients count information
      // Format: output clients <count>
      const clientsMatch = trimmed.match(/^(\S+)\s+clients\s+(\d+)$/)
      if (clientsMatch) {
        const [, outputName, clientsCount] = clientsMatch
        // Store clients count for the output
        if (!monitorCache[outputName]) {
          monitorCache[outputName] = {}
        }
        monitorCache[outputName].clientsCount = parseInt(clientsCount)
      }

      // Parse tags mask information
      // Format: output tags <occupied> <selected> <urgent>
      const tagsMaskMatch = trimmed.match(/^(\S+)\s+tags\s+(\d+)\s+(\d+)\s+(\d+)$/)
      if (tagsMaskMatch) {
        const [, outputName, occupiedMask, selectedMask, urgentMask] = tagsMaskMatch
        if (!monitorCache[outputName]) {
          monitorCache[outputName] = {}
        }
        monitorCache[outputName].occupiedMask = parseInt(occupiedMask)
        monitorCache[outputName].selectedMask = parseInt(selectedMask)
        monitorCache[outputName].urgentMask = parseInt(urgentMask)
      }
    }

    // Flatten all tags from all outputs into a single list
    for (const [outputName, tags] of Object.entries(outputTags)) {
      for (const tag of tags) {
        workspacesList.push(tag)
      }
    }

    // Sort workspaces by tag ID, then by output name
    workspacesList.sort((a, b) => {
      if (a.id !== b.id) {
        return a.id - b.id
      }
      return a.output.localeCompare(b.output)
    })

    // Update workspaces ListModel
    workspaces.clear()
    for (var i = 0; i < workspacesList.length; i++) {
      workspaces.append(workspacesList[i])
    }

    workspaceChanged()
  }

  // Parse windows data
  function parseWindowsData(windowData) {

    const windowsList = []
    windowCache = {}
    let newFocusedIndex = -1

    for (const [outputName, data] of Object.entries(windowData)) {
      if (data.title || data.appId) {
        const windowInfo = {
          "id": outputName, // Use output name as unique identifier for now
          "title": data.title || "",
          "appId": data.appId || "",
          "workspaceId": getCurrentTagId(), // Get current active tag
          "isFocused": false, // Will be determined by focused window detection
          "output": outputName,
          "class": data.appId || "",
          "fullscreen": data.isFullscreen || false,
          "floating": data.isFloating || false,
          "x": data.x || 0,
          "y": data.y || 0,
          "width": data.width || 0,
          "height": data.height || 0
        }

        windowsList.push(windowInfo)
        windowCache[outputName] = windowInfo
      }
    }

    // Try to determine focused window by checking which output is focused
    // This is a heuristic approach since mmsg doesn't provide direct focus info
    for (let i = 0; i < windowsList.length; i++) {
      const window = windowsList[i]
      const outputData = monitorCache[window.output]
      if (outputData && outputData.focused) {
        window.isFocused = true
        newFocusedIndex = i
        break
      }
    }

    // Fallback: assume first window is focused if no output focus info
    if (newFocusedIndex === -1 && windowsList.length > 0) {
      windowsList[0].isFocused = true
      newFocusedIndex = 0
    }

    windows = windowsList

    if (newFocusedIndex !== focusedWindowIndex) {
      focusedWindowIndex = newFocusedIndex
      activeWindowChanged()
    }

    windowListChanged()
  }

  // Get current active tag ID
  function getCurrentTagId() {
    for (const [tagId, tagData] of Object.entries(tagCache)) {
      if (tagData.isActive) {
        return parseInt(tagId)
      }
    }
    return 1 // Default to tag 1
  }

  // Handle events from mmsg -w
  function handleEvent(eventLine) {
    const parts = eventLine.trim().split(/\s+/)
    if (parts.length < 2) return

    const outputName = parts[0]
    const eventType = parts[1]

    // Handle different event types
    switch (eventType) {
      case "tag":
        // Tag state changed
        updateTimer.restart()
        break
      case "title":
      case "appid":
      case "fullscreen":
      case "floating":
        // Window properties changed
        updateTimer.restart()
        break
      case "layout":
        // Layout changed
        updateTimer.restart()
        break
      case "kb_layout":
        // Keyboard layout changed
        const layoutName = parts.slice(2).join(' ')
        if (layoutName && layoutName !== currentKeyboardLayout) {
          currentKeyboardLayout = layoutName
          KeyboardLayoutService.setCurrentLayout(layoutName)
        }
        break
      case "scale_factor":
        // Display scale changed
        queryDisplayScales()
        break
      case "monitor":
        // Monitor configuration changed
        queryDisplayScales()
        updateTimer.restart()
        break
      case "client":
        // Client (window) focus or state changed
        updateTimer.restart()
        break
      case "selmon":
        // Selected monitor changed
        updateTimer.restart()
        break
      default:
        // Unknown event type, trigger general update

        updateTimer.restart()
        break
    }
  }

  // Safe update wrapper
  function safeUpdate() {
    safeUpdateWindows()
    safeUpdateWorkspaces()
    windowListChanged()
  }

  // Safe workspace update
  function safeUpdateWorkspaces() {
    try {
      updateWorkspaces()
    } catch (e) {
      Logger.e("MangoService", "Error updating workspaces:", e)
    }
  }

  // Safe window update
  function safeUpdateWindows() {
    try {
      updateWindows()
    } catch (e) {
      Logger.e("MangoService", "Error updating windows:", e)
    }
  }

  // Public functions
  function switchToWorkspace(workspace) {
    try {
      // MangoWC uses tags 1-9, so switch to tag by ID
      const tagId = workspace.idx || workspace.id || 1
      Quickshell.execDetached(["mmsg", "-d", "view", tagId.toString()])
    } catch (e) {
      Logger.e("MangoService", "Failed to switch workspace:", e)
    }
  }

  function focusWindow(window) {
    try {
      // For MangoWC, we can try to focus windows by switching to their workspace
      // and then using focus commands, or by cycling through windows
      if (window && window.workspaceId) {
        // First switch to the window's workspace/tag
        Quickshell.execDetached(["mmsg", "-d", "view", window.workspaceId.toString()])
        
        // Then try to focus the window by cycling or using window-specific commands
        // This is a limitation of the mmsg interface - we can't directly focus by window ID
        Qt.callLater(() => {
          // Give the workspace switch a moment to complete, then try to find the window
          // For now, we'll use a generic focus command that focuses the main window
          Quickshell.execDetached(["mmsg", "-d", "focusmaster"])
        })
      }
    } catch (e) {
      Logger.e("MangoService", "Failed to focus window:", e)
    }
  }

  function closeWindow(window) {
    try {
      // Close focused window
      Quickshell.execDetached(["mmsg", "-d", "killclient"])
    } catch (e) {
      Logger.e("MangoService", "Failed to close window:", e)
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(["mmsg", "-d", "quit"])
    } catch (e) {
      Logger.e("MangoService", "Failed to logout:", e)
    }
  }
}