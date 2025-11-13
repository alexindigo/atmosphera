import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.Keyboard

Item {
  id: root

  // Properties matching facade interface
  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  // Signals matching facade interface
  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // Mango-specific properties
  property bool initialized: false
  property bool overviewActive: false
  property var workspaceCache: ({})
  property var windowCache: ({})
  property var monitorCache: ({})
  property string currentLayout: ""
  property string currentLayoutSymbol: ""
  property string currentKeyboardLayout: ""

  // Constants
  readonly property var mmsgCommands: ({
    query: {
      workspaces: ["mmsg", "-g", "-t"],
      windows: ["mmsg", "-g", "-c"],
      layout: ["mmsg", "-g", "-l"],
      keyboard: ["mmsg", "-g", "-k"],
      outputs: ["mmsg", "-g", "-A"],
      eventStream: ["mmsg", "-w"]
    },
    action: {
      view: ["mmsg", "-d", "view"],
      tag: ["mmsg", "-t"],
      focusMaster: ["mmsg", "-d", "focusmaster"],
      killClient: ["mmsg", "-d", "killclient"],
      toggleOverview: ["mmsg", "-d", "toggleoverview"],
      setLayout: ["mmsg", "-d", "setlayout"],
      quit: ["mmsg", "-d", "quit"]
    }
  })

  readonly property string overviewLayoutSymbol: "󰃇"
  readonly property int defaultWorkspaceId: 1

  // Debounce timer for updates
  Timer {
    id: updateTimer
    interval: 50
    repeat: false
    onTriggered: safeUpdate()
  }

  // Event stream for real-time updates
  Process {
    id: eventStream
    running: false
    command: mmsgCommands.query.eventStream

    stdout: SplitParser {
      onRead: function (line) {
        try {
          handleEvent(line.trim())
        } catch (e) {
          Logger.e("MangoService", "Event parsing error:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Event stream exited, restarting...")
        restartTimer.start()
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: {
      if (initialized) {
        eventStream.running = true
      }
    }
  }

  // Query processes
  Process {
    id: workspacesProcess
    running: false
    command: mmsgCommands.query.workspaces
    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        workspacesProcess.accumulatedOutput += line + "\n"
      }
    }

    onExited: function (exitCode) {
      if (exitCode === 0) {
        parseWorkspaces(accumulatedOutput)
      } else {
        Logger.e("MangoService", "Workspaces query failed:", exitCode)
      }
      accumulatedOutput = ""
    }
  }

  Process {
    id: windowsProcess
    running: false
    command: mmsgCommands.query.windows
    property string accumulatedOutput: ""
    property var currentWindow: ({})

    onRunningChanged: {
      if (running) {
        windowsProcess.currentWindow = {}
      }
    }

    stdout: SplitParser {
      onRead: function (line) {
        const trimmed = line.trim()
        if (!trimmed) return

        const parts = trimmed.split(' ')
        if (parts.length >= 3) {
          const outputName = parts[0]
          const property = parts[1]
          const value = parts.slice(2).join(' ')

          if (!windowsProcess.currentWindow[outputName]) {
            windowsProcess.currentWindow[outputName] = {
              id: outputName,
              output: outputName
            }
          }

          switch (property) {
            case "title":
              windowsProcess.currentWindow[outputName].title = value
              break
            case "appid":
              windowsProcess.currentWindow[outputName].appId = value
              windowsProcess.currentWindow[outputName].class = value
              break
            case "fullscreen":
              windowsProcess.currentWindow[outputName].fullscreen = (value === "1")
              break
            case "floating":
              windowsProcess.currentWindow[outputName].floating = (value === "1")
              break
            case "x":
              windowsProcess.currentWindow[outputName].x = parseInt(value)
              break
            case "y":
              windowsProcess.currentWindow[outputName].y = parseInt(value)
              break
            case "width":
              windowsProcess.currentWindow[outputName].width = parseInt(value)
              break
            case "height":
              windowsProcess.currentWindow[outputName].height = parseInt(value)
              break
          }
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode === 0) {
        parseWindows(windowsProcess.currentWindow)
      } else {
        Logger.e("MangoService", "Windows query failed:", exitCode)
      }
      accumulatedOutput = ""
      windowsProcess.currentWindow = {}
    }
  }

  Process {
    id: layoutProcess
    running: false
    command: mmsgCommands.query.layout

    stdout: SplitParser {
      onRead: function (line) {
        try {
          const parts = line.trim().split(/\s+/)
          if (parts.length >= 2) {
            const layoutSymbol = parts.slice(1).join(' ')
            handleLayoutChange(layoutSymbol)
          }
        } catch (e) {
          Logger.e("MangoService", "Layout parsing error:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Layout query failed:", exitCode)
      }
    }
  }

  Process {
    id: keyboardProcess
    running: false
    command: mmsgCommands.query.keyboard

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
          Logger.e("MangoService", "Keyboard layout parsing error:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.e("MangoService", "Keyboard query failed:", exitCode)
      }
    }
  }

  Process {
    id: outputsProcess
    running: false
    command: mmsgCommands.query.outputs

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
          Logger.e("MangoService", "Output parsing error:", e, line)
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode === 0) {
        updateDisplayScales()
      } else {
        Logger.e("MangoService", "Outputs query failed:", exitCode)
      }
    }
  }

  // Initialization
  function initialize() {
    if (initialized) {
      Logger.w("MangoService", "Already initialized")
      return
    }

    try {
      Logger.i("MangoService", "Initializing MangoWC service...")
      
      eventStream.running = true
      queryWorkspaces()
      queryWindows()
      queryLayout()
      queryKeyboard()
      queryOutputs()
      
      initialized = true
      Logger.i("MangoService", "Service initialized successfully")
    } catch (e) {
      Logger.e("MangoService", "Initialization failed:", e)
      eventStream.running = true
    }
  }

  // Workspace operations
  function switchToWorkspace(workspace) {
    try {
      const tagId = workspace.idx || workspace.id || defaultWorkspaceId
      const command = mmsgCommands.action.tag.concat([tagId.toString()])
      Quickshell.execDetached(command)
      Logger.d("MangoService", `Switching to workspace ${tagId}`)
    } catch (e) {
      Logger.e("MangoService", "Failed to switch workspace:", e)
    }
  }

  // Window operations
  function focusWindow(window) {
    try {
      if (window && window.workspaceId) {
        const command = mmsgCommands.action.view.concat([window.workspaceId.toString()])
        Quickshell.execDetached(command)
        
        Qt.callLater(() => {
          Quickshell.execDetached(mmsgCommands.action.focusMaster)
        })
      }
    } catch (e) {
      Logger.e("MangoService", "Failed to focus window:", e)
    }
  }

  function closeWindow() {
    try {
      Quickshell.execDetached(mmsgCommands.action.killClient)
    } catch (e) {
      Logger.e("MangoService", "Failed to close window:", e)
    }
  }

  // MangoWC-specific operations
  function toggleOverview() {
    try {
      Quickshell.execDetached(mmsgCommands.action.toggleOverview)
    } catch (e) {
      Logger.e("MangoService", "Failed to toggle overview:", e)
    }
  }

  function setLayout(layoutName) {
    try {
      const command = mmsgCommands.action.setLayout.concat([layoutName])
      Quickshell.execDetached(command)
    } catch (e) {
      Logger.e("MangoService", "Failed to set layout:", e)
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(mmsgCommands.action.quit)
    } catch (e) {
      Logger.e("MangoService", "Failed to logout:", e)
    }
  }

  // Data parsing
  function parseWorkspaces(output) {
    const lines = output.trim().split('\n')
    const workspacesList = []
    const newWorkspaceCache = {}

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) continue

      const match = trimmed.match(/^(\S+)\s+tag\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/)
      if (match) {
        const [, outputName, tagNum, state, clients, focused] = match
        const tagId = parseInt(tagNum)
        
        const isActive = (parseInt(state) & 1) !== 0
        const isUrgent = (parseInt(state) & 2) !== 0
        const isOccupied = parseInt(clients) > 0
        const isFocused = isActive && parseInt(focused) === 1

        const workspaceData = {
          id: tagId,
          idx: tagId,
          name: tagId.toString(),
          output: outputName,
          isActive: isActive,
          isFocused: isFocused,
          isUrgent: isUrgent,
          isOccupied: isOccupied,
          clients: parseInt(clients)
        }

        newWorkspaceCache[tagId] = workspaceData
        workspacesList.push(workspaceData)
      }

      const layoutMatch = trimmed.match(/^(\S+)\s+layout\s+(\S+)$/)
      if (layoutMatch) {
        const [, , layoutSymbol] = layoutMatch
        handleLayoutChange(layoutSymbol)
      }
    }

    if (JSON.stringify(newWorkspaceCache) !== JSON.stringify(workspaceCache)) {
      workspaceCache = newWorkspaceCache
      
      workspacesList.sort((a, b) => {
        if (a.id !== b.id) return a.id - b.id
        return a.output.localeCompare(b.output)
      })

      workspaces.clear()
      for (var i = 0; i < workspacesList.length; i++) {
        workspaces.append(workspacesList[i])
      }
      
      workspaceChanged()
    }
  }

  function parseWindows(windowData) {
    const windowsList = []
    const newWindowCache = {}
    let newFocusedIndex = -1

    for (const [outputName, data] of Object.entries(windowData)) {
      if (data.title || data.appId) {
        const windowInfo = {
          id: outputName,
          title: data.title || "",
          appId: data.appId || "",
          class: data.appId || "",
          workspaceId: getCurrentActiveTagId(),
          isFocused: false,
          output: outputName,
          fullscreen: data.fullscreen || false,
          floating: data.floating || false,
          x: data.x || 0,
          y: data.y || 0,
          width: data.width || 0,
          height: data.height || 0,
          geometry: {
            x: data.x || 0,
            y: data.y || 0,
            width: data.width || 0,
            height: data.height || 0
          }
        }

        windowsList.push(windowInfo)
        newWindowCache[outputName] = windowInfo
      }
    }

    for (let i = 0; i < windowsList.length; i++) {
      const window = windowsList[i]
      const outputData = monitorCache[window.output]
      if (outputData && outputData.focused) {
        window.isFocused = true
        newFocusedIndex = i
        break
      }
    }

    if (JSON.stringify(newWindowCache) !== JSON.stringify(windowCache)) {
      windowCache = newWindowCache
      windows = windowsList
      
      if (newFocusedIndex !== focusedWindowIndex) {
        focusedWindowIndex = newFocusedIndex
        activeWindowChanged()
      }
      
      windowListChanged()
    }
  }

  function handleLayoutChange(layoutSymbol) {
    const wasOverview = overviewActive
    const isOverview = (layoutSymbol === overviewLayoutSymbol)
    
    if (wasOverview !== isOverview) {
      overviewActive = isOverview
      Logger.d("MangoService", `Overview mode: ${overviewActive}`)
    }
    
    if (layoutSymbol !== currentLayoutSymbol) {
      currentLayoutSymbol = layoutSymbol
      currentLayout = layoutSymbol
    }
  }

  function updateDisplayScales() {
    const scales = {}
    for (const [outputName, data] of Object.entries(monitorCache)) {
      scales[outputName] = {
        name: data.name || outputName,
        scale: data.scale || 1.0,
        width: data.width || 0,
        height: data.height || 0,
        refresh_rate: data.refresh_rate || 0,
        x: data.x || 0,
        y: data.y || 0,
        active: data.active || false,
        focused: data.focused || false
      }
    }

    if (CompositorService && CompositorService.onDisplayScalesUpdated) {
      CompositorService.onDisplayScalesUpdated(scales)
    }
    displayScalesChanged()
  }

  // Event handling
  function handleEvent(eventLine) {
    const parts = eventLine.trim().split(/\s+/)
    if (parts.length < 2) return

    const eventType = parts[1]

    switch (eventType) {
      case "tag":
      case "title":
      case "appid":
      case "fullscreen":
      case "floating":
      case "layout":
      case "kb_layout":
      case "scale_factor":
      case "monitor":
      case "client":
      case "selmon":
        updateTimer.restart()
        break
    }
  }

  // Queries
  function queryWorkspaces() {
    workspacesProcess.running = true
  }

  function queryWindows() {
    windowsProcess.running = true
  }

  function queryLayout() {
    layoutProcess.running = true
  }

  function queryKeyboard() {
    keyboardProcess.running = true
  }

  function queryOutputs() {
    outputsProcess.running = true
  }

  // Utilities
  function safeUpdate() {
    try {
      queryWorkspaces()
      queryWindows()
    } catch (e) {
      Logger.e("MangoService", "Safe update failed:", e)
    }
  }

  function getCurrentActiveTagId() {
    for (const [tagId, tagData] of Object.entries(workspaceCache)) {
      if (tagData.isActive) {
        return parseInt(tagId)
      }
    }
    return defaultWorkspaceId
  }
}