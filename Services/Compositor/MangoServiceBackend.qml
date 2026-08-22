import Mango
import QtQuick
import qs.Commons

// mangoqml-backed IPC backend for MangoService.
// Loaded via Loader so systems without qt6-mangowcqml installed degrade
// gracefully (empty workspaces, no windows) instead of failing to load.
Item {
  id: backend

  // ===== BACKEND INTERFACE =====

  // Workspace data (tags from mangowc)
  property ListModel workspaces: ListModel {}
  // Window data (clients from mangowc)
  property var windows: []
  // Focused window index into windows
  property int focusedWindowIndex: -1
  // Active monitor name
  property string selectedMonitor: ""
  // Current layout symbol on the active monitor
  property string currentLayoutSymbol: ""

  // ===== SIGNALS =====

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // ===== INITIALIZATION =====

  Component.onCompleted: {
    Logger.i("MangoService", "Initializing mangoqml backend (mmsg IPC)");
    internal._init();
  }

  // Subscribe to watch streams when the connection state changes
  Connections {
    target: MangoConnection
    function onConnectionStateChanged() {
      if (MangoConnection.isConnected) {
        MangoEvents.subscribeWatchStreams();
      }
    }
  }

  // ===== INTERNAL STATE =====

  QtObject {
    id: internal

    // Screen name → output mapping for multi-monitor support
    property var outputMap: ({})
    // Stable output indices (for workspace ID generation)
    property var outputIndices: ({})
    property int outputCounter: 0
    // Window ID → tag mapping (persistent across rebuilds)
    property var windowTagMap: ({})
    // Window ID → output mapping
    property var windowOutputMap: ({})
    // Toplevel → stable ID mapping
    property var toplevelIdMap: ({})
    property int windowIdCounter: 0

    // Initialize the backend
    function _init() {
      // Connect to mango events
      MangoEvents.clientsChanged.connect(internal.onClientsChanged);
      MangoEvents.monitorsChanged.connect(internal.onMonitorsChanged);
      MangoEvents.tagsChanged.connect(internal.onTagsChanged);
      MangoEvents.focusingClientChanged.connect(internal.onFocusingClientChanged);

      // Subscribe to watch streams when connection is ready
      if (MangoConnection.isConnected) {
        MangoEvents.subscribeWatchStreams();
      }

      // Bootstrap from cached snapshots
      internal.onClientsChanged(MangoEvents.lastClientsSnapshot());
      internal.onMonitorsChanged(MangoEvents.lastMonitorsSnapshot());
      internal.onTagsChanged(MangoEvents.lastTagsSnapshot());
      internal.onFocusingClientChanged(MangoEvents.lastFocusingClientSnapshot());
    }

    // ===== EVENT HANDLERS =====

    function onClientsChanged(clients) {
      internal.rebuildWindows(clients);
    }

    function onMonitorsChanged(monitors) {
      internal.rebuildOutputs(monitors);
      internal.rebuildWorkspaces();
    }

    function onTagsChanged(tags) {
      internal.rebuildTags(tags);
      internal.rebuildWorkspaces();
    }

    function onFocusingClientChanged(client) {
      internal.updateFocus(client);
    }

    // ===== OUTPUT/WORKSPACE MANAGEMENT =====

    function rebuildOutputs(monitors) {
      internal.outputMap = {};
      for (var i = 0; i < monitors.length; i++) {
        const m = monitors[i];
        const name = m.name;
        internal.outputMap[name] = m;

        if (m.active) {
          backend.selectedMonitor = name;
          backend.currentLayoutSymbol = m.layout_symbol || "";
        }
      }
    }

    function getOutputIndex(outputName) {
      if (!(outputName in internal.outputIndices)) {
        internal.outputIndices[outputName] = internal.outputCounter++;
      }
      return internal.outputIndices[outputName];
    }

    function rebuildWorkspaces() {
      const ws = [];
      const monitors = Object.values(internal.outputMap);

      for (const monitor of monitors) {
        const outputName = monitor.name;
        const outputIdx = internal.getOutputIndex(outputName);
        const tags = monitor.tags || [];

        for (const tag of tags) {
          const tagId = tag.index; // mangowc tag indices are 1-based
          const uniqueId = outputIdx * 100 + tagId;

          ws.push({
                    id: uniqueId,
                    idx: tagId,
                    name: tagId.toString(),
                    output: outputName,
                    isActive: tag.is_active,
                    isFocused: tag.is_active && monitor.active,
                    isUrgent: tag.is_urgent,
                    isOccupied: (tag.client_count || 0) > 0
                  });
        }
      }

      ws.sort((a, b) => a.id - b.id);

      backend.workspaces.clear();
      for (const w of ws) {
        backend.workspaces.append(w);
      }

      backend.workspaceChanged();
    }

    function rebuildTags(tags) {
      // Tags come from the all-tags watch stream — flatten per-monitor
      // into a unified tag list with output association
      // (This is handled by rebuildWorkspaces which uses monitor.tags)
    }

    // ===== WINDOW MANAGEMENT =====

    function rebuildWindows(clients) {
      const windows = [];
      let newFocusedIdx = -1;

      for (let i = 0; i < clients.length; i++) {
        const client = clients[i];
        const windowId = internal.getWindowId(client);
        const outputName = internal.getWindowOutput(client, windowId);
        const tagId = internal.getWindowTag(client, windowId);

        if (tagId === null)
          // Skip windows with no known tag

          continue;
        const outputIdx = internal.getOutputIndex(outputName);
        const workspaceId = outputIdx * 100 + tagId;

        const record = {
          id: windowId,
          idx: i,
          appId: client.appid || "",
          title: client.title || "",
          output: outputName,
          workspaceId: workspaceId,
          isFocused: client.is_focused,
          isFloating: client.is_floating,
          isFullscreen: client.is_fullscreen,
          isUrgent: client.is_urgent,
          isScratchpad: client.is_scratchpad,
          handle: client // keep reference for activate/close
        };

        windows.push(record);

        if (client.is_focused) {
          newFocusedIdx = windows.length - 1;
        }
      }

      backend.windows = windows;
      if (newFocusedIdx !== backend.focusedWindowIndex) {
        backend.focusedWindowIndex = newFocusedIdx;
        backend.activeWindowChanged();
      }
      backend.windowListChanged();
    }

    function getWindowId(client) {
      const key = client.id;
      if (!(key in internal.toplevelIdMap)) {
        internal.toplevelIdMap[key] = ++internal.windowIdCounter;
      }
      return internal.toplevelIdMap[key];
    }

    function getWindowOutput(client, windowId) {
      // Priority 1: Focused window matched to output metadata
      if (client.is_focused && client.monitor) {
        internal.windowOutputMap[windowId] = client.monitor;
        return client.monitor;
      }

      // Priority 2: Remembered output
      if (windowId in internal.windowOutputMap) {
        return internal.windowOutputMap[windowId];
      }

      // Priority 3: Client's monitor field
      if (client.monitor) {
        internal.windowOutputMap[windowId] = client.monitor;
        return client.monitor;
      }

      // Fallback: active monitor
      return backend.selectedMonitor || "DP-1";
    }

    function getWindowTag(client, windowId) {
      // Priority 1: Focused window matched to output tag
      if (client.is_focused && client.monitor) {
        const monitor = internal.outputMap[client.monitor];
        if (monitor && monitor.tags) {
          for (const tag of monitor.tags) {
            if (tag.is_active) {
              internal.windowTagMap[windowId] = tag.index;
              return tag.index;
            }
          }
        }
      }

      // Priority 2: Remembered tag
      if (windowId in internal.windowTagMap) {
        return internal.windowTagMap[windowId];
      }

      // Priority 3: Client's tags array (first tag)
      if (client.tags && client.tags.length > 0) {
        const tagId = client.tags[0];
        internal.windowTagMap[windowId] = tagId;
        return tagId;
      }

      return null;
    }

    function updateFocus(client) {
      // Update focused window in the windows list
      const windowId = internal.getWindowId(client);
      let newFocusedIdx = -1;

      for (let i = 0; i < backend.windows.length; i++) {
        if (backend.windows[i].id === windowId) {
          newFocusedIdx = i;
          backend.windows[i].isFocused = true;
        } else {
          backend.windows[i].isFocused = false;
        }
      }

      if (newFocusedIdx !== backend.focusedWindowIndex) {
        backend.focusedWindowIndex = newFocusedIdx;
        backend.activeWindowChanged();
      }
    }
  }

  // ===== PUBLIC API =====

  function initialize() {
    // Initialization is handled by Component.onCompleted
  }

  function switchToWorkspace(workspace) {
    const outputName = workspace.output;
    const tagId = workspace.idx;

    // Use mango dispatch to switch tag
    const mask = 1 << (tagId - 1);
    MangoActions.dispatch("set_tags", [outputName, mask.toString()]);
  }

  function focusWindow(window) {
    if (window.handle && window.handle.id) {
      MangoActions.focusWindow(window.handle.id);
    }
  }

  function closeWindow(window) {
    if (window.handle && window.handle.id) {
      MangoActions.closeWindow(window.handle.id);
    }
  }

  function turnOffMonitors() {
    const monitors = Object.keys(internal.outputMap);
    for (const name of monitors) {
      MangoActions.dispatch("disable_monitor", [name]);
    }
  }

  function turnOnMonitors() {
    const monitors = Object.keys(internal.outputMap);
    for (const name of monitors) {
      MangoActions.dispatch("enable_monitor", [name]);
    }
  }

  function logout() {
    MangoActions.dispatch("quit", []);
  }

  function spawn(command) {
    MangoActions.spawn(command);
  }

  function cycleKeyboardLayout() {
    Logger.w("MangoService", "Keyboard layout cycling not supported via mmsg");
  }

  function getFocusedScreen() {
    return null;
  }
}
