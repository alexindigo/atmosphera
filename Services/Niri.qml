pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var workspaces: []
    property var windows: []
    property var outputs: []
    property int focusedWindowIndex: -1
    property bool inOverview: false

    // Reactive property for focused window title
    property string focusedWindowTitle: "(No active window)"

    // Update the focusedWindowTitle whenever relevant properties change
    function updateFocusedWindowTitle() {
        if (focusedWindowIndex >= 0 && focusedWindowIndex < windows.length) {
            focusedWindowTitle = windows[focusedWindowIndex].title || "(Unnamed window)";
        } else {
            focusedWindowTitle = "(No active window)";
        }
    }
    // Call updateFocusedWindowTitle on changes
    onWindowsChanged: updateFocusedWindowTitle()
    onFocusedWindowIndexChanged: updateFocusedWindowTitle()
    
    Component.onCompleted: {
        eventStream.running = true;
        outputsProcess.running = true;
    }
    
    Process {
        id: outputsProcess
        running: false
        command: ["niri", "msg", "--json", "outputs"]
        
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    const outputsData = JSON.parse(line);
                    const outputsList = [];
                    
                    // Process each output
                    for (const [connector, data] of Object.entries(outputsData)) {
                        const logical = data.logical || {};
                        outputsList.push({
                            connector: connector,
                            name: data.name || connector,
                            make: data.make || "",
                            model: data.model || "",
                            x: logical.x || 0,
                            y: logical.y || 0,
                            width: logical.width || 1920,
                            height: logical.height || 1080,
                            scale: logical.scale || 1.0,
                            transform: logical.transform || "Normal"
                        });
                    }
                    
                    // Sort outputs by position (left to right, top to bottom)
                    outputsList.sort((a, b) => {
                        if (a.x !== b.x) return a.x - b.x;
                        return a.y - b.y;
                    });
                    
                    root.outputs = outputsList;
                } catch (e) {
                    console.error("Failed to parse outputs:", e, line);
                }
            }
        }
    }

    Process {
        id: eventStream        
        running: false
        command: ["niri", "msg", "--json", "event-stream"]

        stdout: SplitParser {
            onRead: data => {
                try {
                    const event = JSON.parse(data.trim());
                    
                    // Handle different event types
                    if (event.WorkspacesChanged) {
                        try {
                            const workspacesData = event.WorkspacesChanged.workspaces;
                            const workspacesList = [];
                            
                            // Process each workspace
                            for (const ws of workspacesData) {
                                workspacesList.push({
                                    id: ws.id,
                                    idx: ws.idx,
                                    name: ws.name || "",
                                    output: ws.output || "",
                                    isFocused: ws.is_focused === true,
                                    isActive: ws.is_active === true,
                                    isUrgent: ws.is_urgent === true,
                                    activeWindowId: ws.active_window_id
                                });
                            }
                            
                            // Sort workspaces by output name and then by ID
                            workspacesList.sort((a, b) => {
                                if (a.output !== b.output) {
                                    return a.output.localeCompare(b.output);
                                }
                                return a.id - b.id;
                            });
                            
                            root.workspaces = workspacesList;
                        } catch (e) {
                            console.error("Error parsing workspaces event:", e);
                        }
                    } else if (event.WindowsChanged) {
                        try {
                            const windowsData = event.WindowsChanged.windows;
                            const windowsList = [];
                            
                            // Process each window
                            for (const win of windowsData) {
                                windowsList.push({
                                    id: win.id,
                                    title: win.title || "",
                                    appId: win.app_id || "",
                                    workspaceId: win.workspace_id || null,
                                    isFocused: win.is_focused === true
                                });
                            }
                            
                            // Sort windows by ID
                            windowsList.sort((a, b) => a.id - b.id);
                            
                            root.windows = windowsList;
                            
                            // Find focused window index
                            for (let i = 0; i < windowsList.length; i++) {
                                if (windowsList[i].isFocused) {
                                    root.focusedWindowIndex = i;
                                    break;
                                }
                            }
                        } catch (e) {
                            console.error("Error parsing windows event:", e);
                        }
                    } else if (event.WorkspaceActivated) {
                        try {
                            const focusedId = parseInt(event.WorkspaceActivated.id);
                            
                            // Update isFocused flag on all workspaces
                            for (let i = 0; i < root.workspaces.length; i++) {
                                // Set isFocused to true only for the activated workspace
                                root.workspaces[i].isFocused = (root.workspaces[i].id === focusedId);
                            }
                            
                            root.workspacesChanged();
                        } catch (e) {
                            console.error("Error parsing workspace activation event:", e);
                        }
                    } else if (event.WindowFocusChanged) {
                        try {
                            const focusedId = event.WindowFocusChanged.id;
                            if (focusedId) {
                                root.focusedWindowIndex = root.windows.findIndex(w => w.id === focusedId);
                                if (root.focusedWindowIndex < 0) {
                                    root.focusedWindowIndex = 0;
                                }
                            } else {
                                root.focusedWindowIndex = -1;
                            }
                        } catch (e) {
                            console.error("Error parsing window focus event:", e);
                        }
                    } else if (event.OverviewOpenedOrClosed) {
                        try {
                            root.inOverview = event.OverviewOpenedOrClosed.is_open === true;
                        } catch (e) {
                            console.error("Error parsing overview state:", e);
                        }
                    }
                } catch (e) {
                    console.error("Error parsing event stream:", e, data);
                }
            }
        }
    }
}
