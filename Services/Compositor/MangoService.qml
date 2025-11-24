import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Keyboard
import qs.Services.UI

Item {
    id: root

    // 1. FACADE INTERFACE
    property ListModel workspaces: ListModel {}
    property var windows: [] 
    property int focusedWindowIndex: -1

    signal workspaceChanged
    signal activeWindowChanged
    signal windowListChanged
    signal displayScalesChanged

    property string selectedMonitor: ""
    property string currentLayoutSymbol: ""
    property bool initialized: false

    // 2. CONFIGURATION
    QtObject {
        id: config
        readonly property int defaultWorkspaceId: 1
        
        // Pre-compiled Regex for Performance
        readonly property var reTagDetail: /^(\S+)\s+tag\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/
        readonly property var reTagBinary: /^(\S+)\s+tags\s+([01]+)\s+([01]+)\s+([01]+)$/
        readonly property var reLayout: /^(\S+)\s+layout\s+(\S+)$/
        readonly property var reMetadata: /^(\S+)\s+(title|appid)\s+(.*)$/
        readonly property var reKbLayout: /^(\S+)\s+kb_layout\s+(.*)$/
        readonly property var reScale: /^(\S+)\s+scale_factor\s+(\d+(\.\d+)?)$/
        
        readonly property var query: ({
            eventStream: ["mmsg", "-w"], 
            monitors:    ["mmsg", "-g", "-o"],
            outputs:     ["mmsg", "-g", "-A"], // Scales
            workspaces:  ["mmsg", "-g", "-t"] 
        })

        readonly property var action: ({
            tag:            ["mmsg", "-s", "-t"],
            view:           ["mmsg", "-s", "-d", "view"],
            toggleOverview: ["mmsg", "-s", "-d", "toggleoverview"],
            setLayout:      ["mmsg", "-s", "-d", "setlayout"],
            killClient:     ["mmsg", "-s", "-d", "killclient"],
            quit:           ["mmsg", "-s", "-q"]
        })
    }

    // 3. LOGIC ENGINE
    QtObject {
        id: internal

        // State
        property var activeTags: ({}) 
        // Map<ToplevelObject, WorkspaceID> - Uses object reference as key
        property var windowStateMap: new Map()
        
        property string mmsgFocusedTitle: ""
        property string mmsgFocusedAppId: ""
        property string currentKbLayout: ""
        
        // Caches
        property var workspaceCache: ({})
        property var monitorScales: ({}) 
        property string lastWindowSig: ""

        // Buffers
        property string streamBuffer: ""

        // --- STREAM PROCESSOR ---
        function processFrame(output) {
            const lines = output.trim().split('\n');
            const newWsList = [];
            const newWsCache = {};
            const processedTags = {}; 
            let metadataChanged = false;

            for (let i = 0; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line) continue;

                // 1. Tag Details
                const tagMatch = line.match(config.reTagDetail);
                if (tagMatch) {
                    const outputName = tagMatch[1];
                    const tagId = parseInt(tagMatch[2]);
                    const state = parseInt(tagMatch[3]);
                    const clients = parseInt(tagMatch[4]);
                    const focused = parseInt(tagMatch[5]);
                    const isActive = (state & 1) !== 0;
                    
                    if (isActive) internal.activeTags[outputName] = tagId;

                    const wsData = {
                        "id": tagId, "idx": tagId, "name": tagId.toString(),
                        "output": outputName,
                        "isActive": isActive,
                        // Check specifically if this monitor is selected for focus highlight
                        "isFocused": isActive && (focused === 1 || outputName === root.selectedMonitor),
                        "isUrgent": (state & 2) !== 0,
                        "isOccupied": clients > 0,
                        "clients": clients
                    };
                    
                    const key = `${outputName}-${tagId}`;
                    newWsCache[key] = wsData;
                    newWsList.push(wsData);
                    processedTags[key] = true;
                    continue;
                }
                
                // 2. Binary Tags (Fill gaps)
                const tagsMatch = line.match(config.reTagBinary);
                if (tagsMatch) {
                    const outputName = tagsMatch[1];
                    const occ = tagsMatch[2];
                    const seltags = tagsMatch[3];
                    const urg = tagsMatch[4];
                    const len = occ.length;

                    for (let j = 0; j < len; j++) {
                        const tagId = j + 1;
                        const charIdx = len - 1 - j; 
                        const key = `${outputName}-${tagId}`;
                        
                        if (processedTags[key]) continue;

                        const isActive = seltags[charIdx] === '1';
                        if (isActive) internal.activeTags[outputName] = tagId;

                        newWsList.push({
                            "id": tagId, "idx": tagId, "name": tagId.toString(),
                            "output": outputName,
                            "isActive": isActive,
                            "isFocused": false,
                            "isUrgent": urg[charIdx] === '1',
                            "isOccupied": occ[charIdx] === '1',
                            "clients": 0
                        });
                    }
                    continue;
                }

                // 3. Metadata
                const metaMatch = line.match(config.reMetadata);
                if (metaMatch) {
                    const prop = metaMatch[2];
                    const val = metaMatch[3];
                    if (prop === "title") internal.mmsgFocusedTitle = val;
                    else if (prop === "appid") internal.mmsgFocusedAppId = val;
                    metadataChanged = true;
                    continue;
                }
                
                // 4. Layout
                const layoutMatch = line.match(config.reLayout);
                if (layoutMatch) {
                    if (layoutMatch[2] !== root.currentLayoutSymbol) {
                        root.currentLayoutSymbol = layoutMatch[2];
                    }
                }

                // 5. Keyboard
                const kbMatch = line.match(config.reKbLayout);
                if (kbMatch) {
                    const kbName = kbMatch[2];
                    if (kbName !== internal.currentKbLayout) {
                        internal.currentKbLayout = kbName;
                        if (KeyboardLayoutService) KeyboardLayoutService.setCurrentLayout(kbName);
                    }
                }
            }

            // Apply
            if (JSON.stringify(newWsCache) !== JSON.stringify(internal.workspaceCache)) {
                internal.workspaceCache = newWsCache;
                newWsList.sort((a, b) => {
                    if (a.id !== b.id) return a.id - b.id;
                    return a.output.localeCompare(b.output);
                });

                root.workspaces.clear();
                for (let k = 0; k < newWsList.length; k++) root.workspaces.append(newWsList[k]);
                root.workspaceChanged();
            }
            
            if (metadataChanged || newWsList.length > 0) {
                internal.updateWindowList();
            }
        }

// --- WINDOW LIST MERGE ---
        function updateWindowList() {
            if (!ToplevelManager.toplevels) return;
            const rawList = ToplevelManager.toplevels.values;
            const finalList = [];
            let newFocusedIdx = -1;
            // Garbage Collection Set
            const currentObjects = new Set();

            // 1. PRE-CALCULATE CAPACITIES
            // Map of "output-tagId" -> remaining client count
            const tagCapacities = {}; 
            for (const key in internal.workspaceCache) {
                tagCapacities[key] = internal.workspaceCache[key].clients || 0;
            }

            const unassignedList = [];

            // 2. PASS 1: IDENTIFY KNOWN WINDOWS
            for (let i = 0; i < rawList.length; i++) {
                const toplevel = rawList[i];
                if (!toplevel || toplevel.outliers) continue;
                
                currentObjects.add(toplevel);

                const appId = toplevel.appId || toplevel.wayland.appId || "";
                const title = toplevel.title || toplevel.wayland.title || "";
                
                let outputName = root.selectedMonitor;
                if (toplevel.outputs && toplevel.outputs.length > 0) {
                    outputName = toplevel.outputs[0].name;
                }

                const currentActiveTag = internal.activeTags[outputName] || config.defaultWorkspaceId;
                let wsId = -1;

                const isFocused = toplevel.activated;
                const isMmsgFocus = (title === internal.mmsgFocusedTitle) && 
                                    (appId === internal.mmsgFocusedAppId);

                // Priority 1: Focused Window (Snap to Active Tag)
                if (isFocused && isMmsgFocus) {
                    wsId = currentActiveTag;
                    internal.windowStateMap.set(toplevel, wsId);
                } 
                // Priority 2: Existing Memory
                else if (internal.windowStateMap.has(toplevel)) {
                    wsId = internal.windowStateMap.get(toplevel);
                } 
                
                const winObj = {
                    "id": `${outputName}-${appId}-${i}`,
                    "title": title,
                    "appId": appId,
                    "class": appId,
                    "workspaceId": wsId, // Might be -1
                    "isFocused": isFocused,
                    "output": outputName,
                    "handle": toplevel,
                    "fullscreen": toplevel.fullscreen,
                    "floating": toplevel.maximized === false && toplevel.fullscreen === false,
                    "sortIdx": i
                };

                if (wsId !== -1) {
                    // This window is accounted for; decrement the tag's capacity
                    const key = `${outputName}-${wsId}`;
                    if (tagCapacities[key] && tagCapacities[key] > 0) {
                        tagCapacities[key]--;
                    }
                    finalList.push(winObj);
                } else {
                    unassignedList.push(winObj);
                }
            }

            // 3. PASS 2: DISTRIBUTE UNASSIGNED WINDOWS
            // Assign remaining windows to tags that still have 'capacity' (client count > 0)
            for (let i = 0; i < unassignedList.length; i++) {
                const win = unassignedList[i];
                const out = win.output;
                let assigned = false;

                // Find a tag on this output that needs clients
                for (const key in tagCapacities) {
                    const wsData = internal.workspaceCache[key];
                    // Match Output and verify capacity
                    if (wsData && wsData.output === out && tagCapacities[key] > 0) {
                        win.workspaceId = wsData.id;
                        internal.windowStateMap.set(win.handle, wsData.id);
                        tagCapacities[key]--;
                        assigned = true;
                        break;
                    }
                }

                // 4. Fallback: Only now do we default to Active Tag if no space matches
                if (!assigned) {
                    const fallback = internal.activeTags[out] || config.defaultWorkspaceId;
                    win.workspaceId = fallback;
                    internal.windowStateMap.set(win.handle, fallback);
                }
                
                finalList.push(win);
            }

            // Restore original order (important for taskbar consistency)
            finalList.sort((a, b) => a.sortIdx - b.sortIdx);
            
            // Find new focused index
            for(let i=0; i<finalList.length; i++) {
                if (finalList[i].isFocused) newFocusedIdx = i;
            }

            // GC: Remove closed windows from memory
            if (internal.windowStateMap.size > rawList.length + 10) {
                for (const key of internal.windowStateMap.keys()) {
                    if (!currentObjects.has(key)) internal.windowStateMap.delete(key);
                }
            }

            // Diff Signature
            const sig = JSON.stringify(finalList.map(w => w.id + w.workspaceId + w.isFocused));
            if (sig !== internal.lastWindowSig) {
                internal.lastWindowSig = sig;
                root.windows = finalList;
                root.windowListChanged();
            }

            if (newFocusedIdx !== root.focusedWindowIndex) {
                root.focusedWindowIndex = newFocusedIdx;
                root.activeWindowChanged();
            }
        }


        // --- SCALES ---
        function updateScales() {
            const scalesMap = {};
            for (const [name, data] of Object.entries(internal.monitorScales)) {
                scalesMap[name] = {
                    "name": name,
                    "scale": data.scale || 1.0,
                    "width": 0, "height": 0, "x": 0, "y": 0 // mmsg lacks geometry
                };
            }
            if (CompositorService && CompositorService.onDisplayScalesUpdated) {
                CompositorService.onDisplayScalesUpdated(scalesMap);
            }
            root.displayScalesChanged();
        }
    }

    // 4. PROCESSES

    Process {
        id: eventStream
        running: false
        command: config.query.eventStream
        stdout: SplitParser {
            onRead: (line) => {
                // Fast Path: Monitor Switch
                if (line.includes("selmon") && line.includes(" 1")) {
                    const parts = line.split(' ');
                    if (parts.length >= 3) root.selectedMonitor = parts[0];
                    return;
                }

                internal.streamBuffer += line + "\n";
                
                // Frame End Detection
                if (line.match(config.reTagBinary)) {
                    internal.processFrame(internal.streamBuffer);
                    internal.streamBuffer = ""; 
                }
            }
        }
        onExited: (code) => { if (code !== 0) restartTimer.start(); }
    }
    Timer { id: restartTimer; interval: 1000; onTriggered: if(initialized) eventStream.running = true }

    Process {
        id: procInitial
        command: config.query.workspaces
        stdout: SplitParser { onRead: (line) => internal.streamBuffer += line + "\n" }
        onExited: (code) => {
            if (code === 0) {
                internal.processFrame(internal.streamBuffer);
                internal.streamBuffer = "";
            }
        }
    }

    Process {
        id: procOutputs
        command: config.query.outputs
        stdout: SplitParser {
            onRead: (line) => {
                const match = line.match(config.reScale);
                if (match) {
                    const out = match[1];
                    const scale = parseFloat(match[2]);
                    if (!internal.monitorScales[out]) internal.monitorScales[out] = {};
                    internal.monitorScales[out].scale = scale;
                }
            }
        }
        onExited: (code) => { if (code === 0) internal.updateScales(); }
    }

    // 5. WAYLAND & INIT

    Connections {
        target: ToplevelManager
        function onToplevelsChanged() { internal.updateWindowList(); }
    }
    Timer {
        interval: 200; running: true; repeat: true
        onTriggered: internal.updateWindowList()
    }

    function initialize() {
        if (initialized) return;
        Logger.i("MangoService", "Service Started");
        
        procOutputs.running = true;
        procInitial.running = true;
        eventStream.running = true;
        
        // One-shot monitor check
        Quickshell.execDetached(["mmsg", "-g", "-o"]); 
        
        initialized = true;
    }

    function queryDisplayScales() { procOutputs.running = true; }

    function switchToWorkspace(workspace) {
        const tagId = workspace.idx || workspace.id || config.defaultWorkspaceId;
        const output = workspace.output || root.selectedMonitor || "";
        const cmd = config.action.tag.slice();
        if (output && Object.keys(internal.monitorScales).length > 1) cmd.push("-o", output);
        cmd.push(tagId.toString());
        Quickshell.execDetached(cmd);
    }

    function focusWindow(window) {
        if (window && window.handle) window.handle.activate();
        else if (window.workspaceId) switchToWorkspace({ id: window.workspaceId, output: window.output });
    }

    function closeWindow(window) {
        if (window && window.handle) window.handle.close();
        else Quickshell.execDetached(config.action.killClient);
    }

    function logout() { Quickshell.execDetached(config.action.quit); }
}
