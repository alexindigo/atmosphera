import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  property int floatingWindowPosition: Number.MAX_SAFE_INTEGER

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  property bool overviewActive: false

  property var keyboardLayouts: []

  property var workspaceMap: ({})
  property var windowMap: ({})
  property var pendingLayoutChanges: []
  property bool activeWindowChangePending: false

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  function initialize() {
    niriEventStream.connected = true;
    niriCommandSocket.connected = true;

    startEventStream();
    updateWorkspaces();
    updateWindows();
    queryDisplayScales();
    Logger.i("NiriService", "Service started");
  }

  // command from https://yalter.github.io/niri/niri_ipc/enum.Request.html
  function sendSocketCommand(sock, command) {
    sock.write(JSON.stringify(command) + "\n");
    sock.flush();
  }

  function startEventStream() {
    sendSocketCommand(niriEventStream, "EventStream");
  }

  function updateWorkspaces() {
    sendSocketCommand(niriCommandSocket, "Workspaces");
  }

  function updateWindows() {
    sendSocketCommand(niriCommandSocket, "Windows");
  }

  function queryDisplayScales() {
    sendSocketCommand(niriCommandSocket, "Outputs");
  }

  function recollectOutputs(outputsData) {
    const scales = {};

    for (const outputName in outputsData) {
      const output = outputsData[outputName];
      if (output && output.name) {
        const logical = output.logical || {};
        const currentModeIdx = output.current_mode || 0;
        const modes = output.modes || [];
        const currentMode = modes[currentModeIdx] || {};

        scales[output.name] = {
          "name": output.name,
          "scale": logical.scale || 1.0,
          "width": logical.width || 0,
          "height": logical.height || 0,
          "x": logical.x || 0,
          "y": logical.y || 0,
          "physical_width": (output.physical_size && output.physical_size[0]) || 0,
          "physical_height": (output.physical_size && output.physical_size[1]) || 0,
          "refresh_rate": currentMode.refresh_rate || 0,
          "vrr_supported": output.vrr_supported || false,
          "vrr_enabled": output.vrr_enabled || false,
          "transform": logical.transform || "Normal"
        };
      }
    }

    if (CompositorService && CompositorService.onDisplayScalesUpdated) {
      CompositorService.onDisplayScalesUpdated(scales);
    }
  }

  function recollectWorkspaces(workspacesData) {
    const workspacesList = [];
    const newWorkspaceMap = {};

    for (const ws of workspacesData) {
      const wsData = {
        "id": ws.id,
        "idx": ws.idx,
        "name": ws.name || "",
        "output": ws.output || "",
        "isFocused": ws.is_focused === true,
        "isActive": ws.is_active === true,
        "isUrgent": ws.is_urgent === true,
        "isOccupied": ws.active_window_id ? true : false
      };
      workspacesList.push(wsData);
      // Build lookup map for O(1) access
      newWorkspaceMap[ws.id] = wsData;
    }

    workspacesList.sort((a, b) => {
                          if (a.output !== b.output) {
                            return a.output.localeCompare(b.output);
                          }
                          return a.idx - b.idx;
                        });

    workspaces.clear();
    for (var i = 0; i < workspacesList.length; i++) {
      workspaces.append(workspacesList[i]);
    }

    // Update workspace lookup map
    workspaceMap = newWorkspaceMap;

    workspaceChanged();
  }

  Socket {
    id: niriCommandSocket
    path: Quickshell.env("NIRI_SOCKET")
    connected: false

    parser: SplitParser {
      onRead: function (line) {
        try {
          const data = JSON.parse(line);

          if (data && data.Ok) {
            const res = data.Ok;
            if (res.Windows) {
              recollectWindows(res.Windows);
            } else if (res.Outputs) {
              recollectOutputs(res.Outputs);
            } else if (res.Workspaces) {
              recollectWorkspaces(res.Workspaces);
            }
          } else {
            Logger.e("NiriService", "Niri returned an error:", data.Err, line);
          }
        } catch (e) {
          Logger.e("NiriService", "Failed to parse data from socket:", e, line);
          return;
        }
      }
    }
  }

  Socket {
    id: niriEventStream
    path: Quickshell.env("NIRI_SOCKET")
    connected: false

    parser: SplitParser {
      onRead: data => {
                try {
                  const event = JSON.parse(data.trim());

                  if (event.WorkspacesChanged) {
                    recollectWorkspaces(event.WorkspacesChanged.workspaces);
                  } else if (event.WindowOpenedOrChanged) {
                    handleWindowOpenedOrChanged(event.WindowOpenedOrChanged);
                  } else if (event.WindowClosed) {
                    handleWindowClosed(event.WindowClosed);
                  } else if (event.WindowsChanged) {
                    handleWindowsChanged(event.WindowsChanged);
                  } else if (event.WorkspaceActivated) {
                    updateWorkspaces();
                  } else if (event.WindowFocusChanged) {
                    handleWindowFocusChanged(event.WindowFocusChanged);
                  } else if (event.WindowLayoutsChanged) {
                    handleWindowLayoutsChanged(event.WindowLayoutsChanged);
                  } else if (event.OverviewOpenedOrClosed) {
                    handleOverviewOpenedOrClosed(event.OverviewOpenedOrClosed);
                  } else if (event.OutputsChanged) {
                    queryDisplayScales();
                  } else if (event.ConfigLoaded) {
                    queryDisplayScales();
                  } else if (event.KeyboardLayoutsChanged) {
                    handleKeyboardLayoutsChanged(event.KeyboardLayoutsChanged);
                  } else if (event.KeyboardLayoutSwitched) {
                    handleKeyboardLayoutSwitched(event.KeyboardLayoutSwitched);
                  }
                } catch (e) {
                  Logger.e("NiriService", "Error parsing event stream:", e, data);
                }
              }
    }
  }

  function getWindowPosition(layout) {
    if (layout.pos_in_scrolling_layout) {
      return {
        "x": layout.pos_in_scrolling_layout[0],
        "y": layout.pos_in_scrolling_layout[1]
      };
    } else {
      return {
        "x": floatingWindowPosition,
        "y": floatingWindowPosition
      };
    }
  }

  function getWindowOutput(win) {
    const ws = workspaceMap[win.workspace_id];
    return ws ? ws.output : null;
  }

  function getWindowData(win) {
    return {
      "id": win.id,
      "title": win.title || "",
      "appId": win.app_id || "",
      "workspaceId": win.workspace_id || -1,
      "isFocused": win.is_focused === true,
      "output": getWindowOutput(win) || "",
      "position": getWindowPosition(win.layout)
    };
  }

  function compareWindows(a, b) {
    if (a.workspaceId !== b.workspaceId) {
      return a.workspaceId - b.workspaceId;
    }
    if (a.position.x !== b.position.x) {
      return a.position.x - b.position.x;
    }
    return a.position.y - b.position.y;
  }

  function recollectWindows(windowsData) {
    const windowsList = [];
    const newWindowMap = {};
    for (const win of windowsData) {
      const windowData = getWindowData(win);
      windowsList.push(windowData);
      newWindowMap[windowData.id] = windowData;
    }
    windowsList.sort(compareWindows);
    windows = windowsList;
    windowMap = newWindowMap;
    windowListChanged();

    focusedWindowIndex = -1;
    for (var i = 0; i < windowsList.length; i++) {
      if (windowsList[i].isFocused) {
        focusedWindowIndex = i;
        break;
      }
    }
    activeWindowChanged();
  }

  function handleWindowOpenedOrChanged(eventData) {
    try {
      const windowData = eventData.window;
      const windowId = windowData.id;
      const existingWindow = windowMap[windowId];
      const newWindow = getWindowData(windowData);

      if (existingWindow) {
        const existingIndex = windows.indexOf(existingWindow);
        if (existingIndex >= 0) {
          windows[existingIndex] = newWindow;
        }
      } else {
        windows.push(newWindow);
      }
      windowMap[windowId] = newWindow;
      windows.sort(compareWindows);

      if (newWindow.isFocused) {
        const oldFocusedIndex = focusedWindowIndex;
        focusedWindowIndex = windows.indexOf(newWindow);

        if (oldFocusedIndex !== focusedWindowIndex) {
          if (oldFocusedIndex >= 0 && oldFocusedIndex < windows.length) {
            windows[oldFocusedIndex].isFocused = false;
          }
          activeWindowChanged();
        }
      }

      windowListChanged();
    } catch (e) {
      Logger.e("NiriService", "Error handling WindowOpenedOrChanged:", e);
    }
  }

  function handleWindowClosed(eventData) {
    try {
      const windowId = eventData.id;
      const window = windowMap[windowId];

      if (window) {
        const windowIndex = windows.indexOf(window);

        if (windowIndex >= 0) {
          if (windowIndex === focusedWindowIndex) {
            focusedWindowIndex = -1;
            activeWindowChanged();
          } else if (focusedWindowIndex > windowIndex) {
            focusedWindowIndex--;
          }

          windows.splice(windowIndex, 1);
          delete windowMap[windowId];
          windowListChanged();
        }
      }
    } catch (e) {
      Logger.e("NiriService", "Error handling WindowClosed:", e);
    }
  }

  function handleWindowsChanged(eventData) {
    try {
      const windowsData = eventData.windows;
      recollectWindows(windowsData);
    } catch (e) {
      Logger.e("NiriService", "Error handling WindowsChanged:", e);
    }
  }

  function handleWindowFocusChanged(eventData) {
    try {
      const focusedId = eventData.id;

      if (windows[focusedWindowIndex]) {
        windows[focusedWindowIndex].isFocused = false;
      }

      if (focusedId) {
        const focusedWindow = windowMap[focusedId];
        const newIndex = focusedWindow ? windows.indexOf(focusedWindow) : -1;

        if (newIndex >= 0 && newIndex < windows.length) {
          windows[newIndex].isFocused = true;
        }

        focusedWindowIndex = newIndex >= 0 ? newIndex : -1;
      } else {
        focusedWindowIndex = -1;
      }

      // Throttle activeWindowChanged to avoid excessive emissions during hover
      if (!activeWindowChangePending) {
        activeWindowChangePending = true;
        activeWindowChangeTimer.restart();
      }
    } catch (e) {
      Logger.e("NiriService", "Error handling WindowFocusChanged:", e);
    }
  }

  Timer {
    id: activeWindowChangeTimer
    interval: 100  // 100ms throttle for focus changes
    onTriggered: {
      activeWindowChangePending = false;
      activeWindowChanged();
    }
  }

  function handleWindowLayoutsChanged(eventData) {
    try {
      // Accumulate pending changes
      for (const change of eventData.changes) {
        pendingLayoutChanges.push(change);
      }

      // Process after a short delay to batch multiple changes
      layoutChangeTimer.restart();
    } catch (e) {
      Logger.e("NiriService", "Error handling WindowLayoutChanged:", e);
    }
  }

  Timer {
    id: layoutChangeTimer
    interval: 150  // 150ms debounce - batches rapid position updates during hover
    onTriggered: {
      if (pendingLayoutChanges.length === 0)
        return;

      // Process all pending changes
      let needsSort = false;
      const oldOrder = windows.map(w => w.id).join(',');

      for (const change of pendingLayoutChanges) {
        const windowId = change[0];
        const layout = change[1];
        const window = windowMap[windowId];
        if (window) {
          const newPosition = getWindowPosition(layout);
          // Only update if position actually changed
          if (window.position.x !== newPosition.x || window.position.y !== newPosition.y) {
            window.position = newPosition;
            needsSort = true;
          }
        }
      }

      // Clear pending changes
      pendingLayoutChanges = [];

      // Only sort if positions changed
      if (needsSort) {
        windows.sort(compareWindows);
        const newOrder = windows.map(w => w.id).join(',');

        if (oldOrder !== newOrder) {
          windowListChanged();
        }
      }
    }
  }

  function handleOverviewOpenedOrClosed(eventData) {
    try {
      overviewActive = eventData.is_open;
      Logger.d("NiriService", "Overview opened or closed:", eventData.is_open);
    } catch (e) {
      Logger.e("NiriService", "Error handling OverviewOpenedOrClosed:", e);
    }
  }

  function handleKeyboardLayoutsChanged(eventData) {
    try {
      keyboardLayouts = eventData.keyboard_layouts.names;
      const layoutName = keyboardLayouts[eventData.keyboard_layouts.current_idx];
      KeyboardLayoutService.setCurrentLayout(layoutName);
      Logger.d("NiriService", "Keyboard layouts changed:", keyboardLayouts.toString());
    } catch (e) {
      Logger.e("NiriService", "Error handling keyboardLayoutsChanged:", e);
    }
  }

  function handleKeyboardLayoutSwitched(eventData) {
    try {
      const layoutName = keyboardLayouts[eventData.idx];
      KeyboardLayoutService.setCurrentLayout(layoutName);
      Logger.d("NiriService", "Keyboard layout switched:", layoutName);
    } catch (e) {
      Logger.e("NiriService", "Error handling KeyboardLayoutSwitched:", e);
    }
  }

  function switchToWorkspace(workspace) {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", workspace.idx.toString()]);
    } catch (e) {
      Logger.e("NiriService", "Failed to switch workspace:", e);
    }
  }

  function focusWindow(window) {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", window.id.toString()]);
    } catch (e) {
      Logger.e("NiriService", "Failed to switch window:", e);
    }
  }

  function closeWindow(window) {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "close-window", "--id", window.id.toString()]);
    } catch (e) {
      Logger.e("NiriService", "Failed to close window:", e);
    }
  }

  function logout() {
    try {
      Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]);
    } catch (e) {
      Logger.e("NiriService", "Failed to logout:", e);
    }
  }
}
