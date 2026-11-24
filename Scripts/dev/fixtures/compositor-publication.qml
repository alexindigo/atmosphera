// Private shell for compositor-publication-units.py. Never imported by the
// production shell. Drives the real CompositorService facade from a scripted
// backend in both notification orders and records what every facade
// notification callback can read at that moment.
import QtQuick
import Quickshell
import qs.Services.Compositor

ShellRoot {
  id: root
  property var records: []
  property var publications: []
  property string step: ""
  readonly property string boundTitle: CompositorService.getFocusedWindowTitle()

  QtObject {
    id: fake
    property ListModel workspaces: ListModel {}
    property var windows: []
    property var focusedWindowId: null
    signal workspaceChanged
    signal activeWindowChanged
    signal windowListChanged
    function initialize() {
    }
  }

  QtObject {
    id: niri
    property var workspaces: ({
                                count: 0,
                                get: () => null
                              })
    property var windows: []
    property var focusedWindowId: null
    property var focusedWorkspaceId: null
    property bool overviewActive: false
    property bool ready: false
    signal statePublished
    signal workspaceChanged
    signal activeWindowChanged
    signal windowListChanged
  }

  function view(signalName) {
    const focused = CompositorService.getFocusedWindow();
    const rows = [];
    for (let i = 0; i < CompositorService.windows.count; i++) {
      const row = CompositorService.windows.get(i);
      rows.push({
                  id: row.id,
                  title: row.title,
                  isFocused: row.isFocused
                });
    }
    const id = CompositorService.focusedWindowId === undefined ? "absent" : CompositorService.focusedWindowId;
    const index = CompositorService.focusedWindowIndex;
    const atIndex = index >= 0 && index < rows.length ? rows[index] : null;
    const title = CompositorService.getFocusedWindowTitle();
    const flagged = rows.filter(row => row.isFocused).map(row => row.id);
    const expected = atIndex ? atIndex.id : null;
    const checks = {
      index_names_id: id === "absent" || id === expected,
      getter: (focused ? focused.id : null) === expected,
      getter_title: !focused || focused.title === title,
      title: title === (atIndex ? atIndex.title : ""),
      // A consumer binding is current once the facade signals; inside a
      // property-change handler other bindings may still be pending.
      bound_title: (signalName !== "windowListChanged" && signalName !== "activeWindowChanged") || boundTitle === title,
      one_flagged_row: JSON.stringify(flagged) === JSON.stringify(expected === null ? [] : [expected])
    };
    return {
      step: step,
      signal: signalName,
      focusedWindowId: id,
      focusedWindowIndex: index,
      focused: focused ? focused.id : null,
      title: title,
      boundTitle: boundTitle,
      rows: rows,
      checks: checks,
      coherent: Object.keys(checks).every(key => checks[key])
    };
  }
  function record(signalName) {
    records.push(view(signalName));
  }
  onBoundTitleChanged: record("boundTitle")

  Connections {
    target: CompositorService
    ignoreUnknownSignals: true
    function onSnapshotChanged() {
      const s = CompositorService.snapshot;
      const current = CompositorService.getCurrentWorkspace();
      root.publications.push({
                               snapshot: s,
                               coherent: s.focusedWindowId === CompositorService.focusedWindowId && s.focusedWorkspaceId === (current?.id ?? null) && s.windows.length === CompositorService.windows.count && s.workspaces.length === CompositorService.workspaces.count && s.overviewActive === CompositorService.overviewActive
                             });
    }
    function onWindowListChanged() {
      root.record("windowListChanged");
    }
    function onActiveWindowChanged() {
      root.record("activeWindowChanged");
    }
    function onFocusedWindowIdChanged() {
      root.record("focusedWindowIdChanged");
    }
    function onFocusedWindowIndexChanged() {
      root.record("focusedWindowIndexChanged");
    }
  }

  function w(id, title) {
    return {
      id: id,
      title: title || ("Window " + id),
      appId: "fixture." + id,
      workspaceId: 1
    };
  }

  // windows: null keeps the current array (no list change). order: which
  // backend notifications follow the state change, in that order.
  readonly property var steps: [
    {
      name: "open-a-list-first",
      windows: [w(1)],
      focused: 1,
      order: ["list", "active"]
    },
    {
      name: "open-b-list-first",
      windows: [w(1), w(2)],
      focused: 2,
      order: ["list", "active"]
    },
    {
      name: "open-c-active-first",
      windows: [w(1), w(2), w(3)],
      focused: 3,
      order: ["active", "list"]
    },
    {
      name: "focus-a-only",
      windows: null,
      focused: 1,
      order: ["active"]
    },
    {
      name: "focus-before-membership",
      windows: null,
      focused: 4,
      order: ["active"]
    },
    {
      name: "membership-after-focus",
      windows: [w(1), w(2), w(3), w(4)],
      focused: 4,
      order: ["list"]
    },
    {
      name: "list-with-stale-focus-then-focus",
      windows: [w(1), w(2), w(3), w(4), w(5)],
      focused: 4,
      order: ["list"]
    },
    {
      name: "focus-new-e",
      windows: null,
      focused: 5,
      order: ["active"]
    },
    {
      name: "same-id-title-change",
      windows: [w(1), w(2), w(3), w(4), w(5, "Renamed 5")],
      focused: 5,
      order: ["list", "active"]
    },
    {
      name: "reorder-focused-moves",
      windows: [w(5, "Renamed 5"), w(1), w(2), w(3), w(4)],
      focused: 5,
      order: ["list"]
    },
    {
      name: "close-unfocused-b",
      windows: [w(5, "Renamed 5"), w(1), w(3), w(4)],
      focused: 5,
      order: ["list"]
    },
    {
      name: "close-focused-e-active-first",
      windows: [w(1), w(3), w(4)],
      focused: 3,
      order: ["active", "list"]
    },
    {
      name: "close-focused-c-list-first",
      windows: [w(1), w(4)],
      focused: 1,
      order: ["list", "active"]
    },
    {
      name: "focus-none",
      windows: null,
      focused: null,
      order: ["active"]
    },
    {
      name: "focus-returns",
      windows: null,
      focused: 4,
      order: ["active"]
    },
    {
      name: "empty",
      windows: [],
      focused: null,
      order: ["list", "active"]
    }
  ]

  function run() {
    CompositorService.backend = fake;
    CompositorService.setupBackendConnections();
    const results = [];
    for (const s of steps) {
      step = s.name;
      records = [];
      if (s.windows !== null)
        fake.windows = s.windows;
      fake.focusedWindowId = s.focused;
      for (const kind of s.order) {
        if (kind === "list")
          fake.windowListChanged();
        else
          fake.activeWindowChanged();
      }
      const final = view("final");
      const member = fake.windows.some(row => row.id === s.focused);
      const expectedFocus = member ? s.focused : null;
      const settled = final.coherent && (final.focusedWindowId === "absent" ? final.focused === expectedFocus : final.focusedWindowId === expectedFocus);
      results.push({
                     name: s.name,
                     order: s.order,
                     records: records.slice(),
                     final: final,
                     expectedFocus: expectedFocus,
                     settled: settled,
                     notified: records.some(r => r.signal === "windowListChanged" || r.signal === "activeWindowChanged"),
                     passed: settled && records.every(r => r.coherent)
                   });
    }
    results.push(snapshotCase());
    console.info("PUBLICATION_RESULT|" + JSON.stringify(results));
    Qt.exit(0);
  }

  function snapshotCase() {
    CompositorService.backend = niri;
    CompositorService.setupBackendConnections();
    publications = [];
    const unseen = CompositorService["snapshot"];
    niri.ready = true;
    niri.statePublished();
    const empty = CompositorService["snapshot"];
    const workspace = {
      id: "0",
      idx: 1,
      isFocused: true
    };
    niri.workspaces = {
      count: 1,
      get: () => workspace
    };
    niri.focusedWorkspaceId = workspace.id;
    niri.focusedWindowId = "9007199254740993";
    niri.windows = [w("9007199254740992"), w(niri.focusedWindowId)];
    niri.statePublished();
    const full = CompositorService["snapshot"];
    niri.statePublished();
    niri.overviewActive = true;
    niri.statePublished();
    const opened = CompositorService["snapshot"];
    niri.overviewActive = false;
    niri.statePublished();
    const closed = CompositorService["snapshot"];
    niri.ready = false;
    niri.focusedWorkspaceId = null;
    niri.focusedWindowId = null;
    niri.workspaces = {
      count: 0,
      get: () => null
    };
    niri.windows = [];
    niri.statePublished();
    const reset = CompositorService["snapshot"];
    const overviewPublished = unseen.overviewActive === false && full.overviewActive === false && opened.overviewActive === true && closed.overviewActive === false && reset.overviewActive === false && opened.revision === full.revision + 1 && closed.revision === opened.revision + 1;
    const passed = unseen?.ready === false && empty?.ready === true && empty.workspaces.length === 0 && empty.windows.length === 0 && full?.ready === true && full.focusedWorkspaceId === "0" && full.workspaces[0].id === "0" && full.focusedWindowId === "9007199254740993" && full.windows[0].id === "9007199254740992" && full.windows[1].isFocused && reset?.ready
          === false && reset.workspaces.length === 0 && reset.windows.length === 0 && reset.focusedWindowId === null && reset.focusedWorkspaceId === null && empty.revision === unseen.revision + 1 && full.revision === empty.revision + 1 && reset.revision === closed.revision + 1 && publications.length === 5 && publications.every(p => p.coherent)
          && overviewPublished;
    return {
      name: "coherent replace-only snapshots, including ready-empty, overview and disconnect",
      passed: passed,
      settled: passed,
      records: publications.map(p => ({
        signal: "snapshotChanged",
        coherent: p.coherent
      })),
    publications: publications
  };
  }

    Component.onCompleted: Qt.callLater(run)
  }
