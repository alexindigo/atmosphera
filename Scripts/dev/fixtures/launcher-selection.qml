import QtQuick
import Quickshell
import Quickshell.Io
import "../../../Modules/Panels/Launcher/Helpers/LauncherSelection.js" as Selection
import "../../../Modules/Panels/Launcher"
import qs.Commons

ShellRoot {
  id: root
  property int stage: 0
  property int failed: 0
  property bool pointerPending: false
  property point requestedPointer
  property int pointerWaitTicks: 0
  property int keyboardWaitTicks: 0
  function same(name, actual, expected) {
    const passed = JSON.stringify(actual) === JSON.stringify(expected);
    if (!passed)
      failed++;
    console.log("LAUNCHER_SELECTION|" + JSON.stringify({
                                                         test: name,
                                                         pass: passed,
                                                         actual: actual,
                                                         expected: expected
                                                       }));
  }
  function row(id) {
    return {
      appId: id,
      name: id,
      icon: "application-x-executable",
      isImage: false,
      provider: provider
    };
  }
  QtObject {
    id: provider
    property bool handleSearch: true
    property string supportedLayouts: "both"
    property var rows: []
    property int prepared: 0
    function getResults(query) {
      return rows;
    }
    function prepareItem(item) {
      prepared++;
    }
  }
  FloatingWindow {
    id: window
    title: "Launcher Selection Test"
    implicitWidth: 1000
    implicitHeight: 700
    LauncherCore {
      id: core
      anchors.fill: parent
    }
  }
  Process {
    id: pointer
  }
  Process {
    id: keyboard
  }
  Process {
    id: fullscreen
    command: ["swaymsg", "[title=\"Launcher Selection Test\"]", "fullscreen", "enable"]
  }
  function delegates(item, found) {
    if (!item)
      return;
    if (item.isSelected !== undefined && item.index !== undefined && item.width > 0 && item.height > 0)
      found.push(item);
    for (const child of item.children || [])
      delegates(child, found);
  }
  function rows() {
    const found = [];
    delegates(core.resultsView, found);
    return found;
  }
  function many(prefix, count, reversed) {
    const out = [];
    for (let i = 0; i < count; i++)
      out.push(root.row(prefix + (reversed ? count - 1 - i : i)));
    return out;
  }
  // Delegates the view created synchronously for the last refresh outside its
  // area. Positioning at the top (where both refreshes leave the view) applies
  // its pending changes now, as its next polish would, without scrolling;
  // asynchronously incubated rows are not created yet.
  function createdOutsideView(before) {
    const view = core.resultsView;
    view.positionViewAtIndex(0, ListView.Beginning);
    return root.rows().filter(item => item.index >= 0 && before.indexOf(item) === -1).filter(item => {
      const y = item.mapToItem(view, 0, 0).y;
      return y + item.height <= 0 || y >= view.height;
    }).length;
  }
  // Live delegates in row order (released ones have index -1).
  function shown() {
    return root.rows().filter(item => item.index >= 0 && item.visible).sort((a, b) => a.index - b.index);
  }
  function moveTo(index, dx) {
    const target = rows().find(item => item.index === index);
    if (!target) {
      same("pointer-target-" + stage, null, index);
      return;
    }
    const point = target.mapToItem(null, target.width / 2 + dx, target.height / 2);
    requestedPointer = Qt.point(Math.round(point.x), Math.round(point.y));
    pointerPending = true;
    pointerWaitTicks = 0;
    pointer.command = ["swaymsg", "seat", "seat0", "cursor", "set", String(Math.round(point.x)), String(Math.round(point.y))];
    pointer.running = true;
  }
  function keyUp() {
    keyboard.command = ["python3", "-B", Quickshell.env("LAUNCHER_INPUT_HELPER"), "key", "103:1", "103:0"];
    keyboard.running = true;
  }
  Timer {
    interval: 350
    repeat: true
    running: true
    onTriggered: {
      // A successful compositor command is not an acknowledgement that Qt has
      // consumed its motion. Wait for the core's observed coordinates before
      // judging selection; keep the same selection/highlight assertions.
      if (root.pointerPending) {
        if (!pointer.running && Math.abs(core.globalLastMouseX - root.requestedPointer.x) < 2 && Math.abs(core.globalLastMouseY - root.requestedPointer.y) < 2) {
          root.pointerPending = false;
        } else if (++root.pointerWaitTicks < 12) {
          return;
        } else {
          root.pointerPending = false;
          root.same("pointer-delivery-" + root.stage, false, true);
        }
      }
      // Likewise a launched key command is judged only after the private
      // keyboard owner acknowledged it (the helper exits on its OK), never on
      // a fixed tick that a slow helper start can outrun.
      if (keyboard.running) {
        if (++root.keyboardWaitTicks < 20)
          return;
        root.same("keyboard-delivery-" + root.stage, false, true);
      }
      root.keyboardWaitTicks = 0;
      switch (root.stage++) {
      case 0:
        Settings.data.general.animationDisabled = true;
        Settings.data.appLauncher.viewMode = "list";
        fullscreen.running = true;
        provider.rows = [root.row("alpha"), root.row("beta"), root.row("gamma")];
        core.providers = [provider];
        core.isOpen = true;
        break;
      case 1:
        root.same("open-top", core.selectedIndex, 0);
        // A refresh producing the same items (new objects, as every query and
        // async re-projection does) keeps every delegate and prepares nothing.
        const kept = root.shown();
        const preparedBefore = provider.prepared;
        provider.rows = [root.row("alpha"), root.row("beta"), root.row("gamma")];
        core.updateResults();
        const again = root.shown();
        root.same("identical-refresh-keeps-delegates", again.length === 3 && again.every((item, i) => item === kept[i]), true);
        root.same("identical-refresh-prepares-nothing", provider.prepared - preparedBefore, 0);
        // A narrowing refresh only removes rows: survivors keep their delegates.
        provider.rows = [root.row("beta"), root.row("gamma")];
        core.updateResults();
        const narrowed = root.shown();
        root.same("narrowing-keeps-survivors", narrowed.length === 2 && narrowed[0] === kept[1] && narrowed[1] === kept[2], true);
        // Large refreshes reset the view: the selection follows its item (or
        // the top after a query) and only shown rows are created synchronously.
        provider.rows = root.many("r", 60, false);
        core.updateResults();
        // The preserved item stays on screen (index 0 -> 3), so the view does not
        // scroll to follow the selection and only the refresh creates rows.
        core.selectedIndex = 0;
        let before = root.rows();
        // A re-rank as a narrowing keystroke produces it: a few new rows on top,
        // the survivors in a different order.
        const reranked = [root.row("n0"), root.row("n1"), root.row("n2")];
        for (let i = 0; i < 60; i++)
          reranked.push(root.row("r" + ((i * 7) % 60)));
        provider.rows = reranked;
        core.updateResults();
        root.same("large-rerank-keeps-selection", [core.selectedIndex, core.results[core.selectedIndex].appId], [3, "r0"]);
        root.same("large-rerank-creates-only-shown-rows", root.createdOutsideView(before), 0);
        provider.rows = [root.row("x0")];
        core.updateResults();
        before = root.rows();
        provider.rows = root.many("e", 80, false);
        core.searchText = "first query";
        root.same("large-insert-selects-top", [core.selectedIndex, core.results[core.selectedIndex].appId], [0, "e0"]);
        root.same("large-insert-creates-only-shown-rows", root.createdOutsideView(before), 0);
        // A refresh that moves the selection off a retained row moves the
        // highlight at once; only navigation animates it (as on main, whose
        // refreshes rebuilt every row).
        Settings.data.general.animationDisabled = false;
        provider.rows = [root.row("alpha"), root.row("beta"), root.row("gamma")];
        core.searchText = "";
        core.updateResults();
        core.selectedIndex = 0;
        // Apply the view's pending changes (as its next polish would) before reading rows.
        const delegateOf = id => {
          core.resultsView.positionViewAtIndex(0, ListView.Beginning);
          return root.shown().find(item => item.row.appId === id);
        };
        const alphaRow = delegateOf("alpha");
        provider.rows = [root.row("beta"), root.row("alpha"), root.row("gamma")];
        core.searchText = "query moves the selection";
        root.same("refresh-highlight-snaps", [delegateOf("alpha") === alphaRow, Qt.colorEqual(alphaRow.color, AtmoColor.mSurfaceVariant),
                                             Qt.colorEqual(delegateOf("beta").color, AtmoColor.mHover)], [true, true, true]);
        core.keyboardSelection(core.selectNextWrapped);
        root.same("navigation-highlight-animates", [core.results[core.selectedIndex].appId, Qt.colorEqual(alphaRow.color, AtmoColor.mHover)], ["alpha", false]);
        Settings.data.general.animationDisabled = true;
        provider.rows = [root.row("alpha"), root.row("beta"), root.row("gamma")];
        core.searchText = "";
        core.updateResults();
        core.selectedIndex = 0;
        core.selectedIndex = 2;
        provider.rows = [root.row("beta"), root.row("gamma"), root.row("zeta")];
        core.updateResults();
        root.same("refresh-preserves-nontop-identity", [core.selectedIndex, core.results[core.selectedIndex].appId], [1, "gamma"]);
        core.searchText = "different query";
        root.same("query-resets-top", core.selectedIndex, 0);
        core.selectedIndex = 2;
        provider.rows = [root.row("beta"), root.row("gamma")];
        core.updateResults();
        root.same("removed-clamps", core.selectedIndex, 1);
        provider.rows = [];
        core.updateResults();
        root.same("empty-selection", core.selectedIndex, -1);
        const other = {};
        root.same("provider-identity", Selection.afterRefresh([
                                                                {
                                                                  appId: "same",
                                                                  provider: other
                                                                },
                                                                {
                                                                  appId: "same",
                                                                  provider: provider
                                                                }
                                                              ], {
                                                                appId: "same",
                                                                provider: provider
                                                              }, 0, false), 1);
        root.same("clipboard-identity", Selection.afterRefresh([
                                                                 {
                                                                   clipboardId: "b"
                                                                 },
                                                                 {
                                                                   clipboardId: "a"
                                                                 }
                                                               ], {
                                                                 clipboardId: "a"
                                                               }, 0, false), 1);
        root.same("window-id-zero", Selection.afterRefresh([
                                                             {
                                                               windowId: 1
                                                             },
                                                             {
                                                               windowId: 0
                                                             }
                                                           ], {
                                                             windowId: 0
                                                           }, 0, false), 1);
        provider.rows = [root.row("alpha"), root.row("beta"), root.row("gamma")];
        core.searchText = "";
        core.selectedIndex = 0;
        break;
      case 2:
        root.moveTo(1, 0);
        break;
      case 3:
        root.moveTo(2, 0);
        break;
      case 4:
        root.same("list-pointer-selects", core.selectedIndex, 2);
        keyboard.command = ["python3", "-B", Quickshell.env("LAUNCHER_INPUT_HELPER"), "type", "q"];
        keyboard.running = true;
        break;
      case 5:
        root.same("typed-query-resets-selection", [core.searchText, core.selectedIndex], ["q", 0]);
        root.same("query-suppresses-stationary-hover", core.ignoreMouseHover, true);
        core.selectedIndex = 2;
        root.keyUp();
        break;
      case 6:
        root.same("list-one-highlight-after-key", root.rows().filter(item => item.isSelected).map(item => item.index), [1]);
        root.same("keyboard-suppresses-stationary-hover", core.ignoreMouseHover, true);
        const selected = root.rows().find(item => item.isSelected);
        const top = selected.mapToItem(core.resultsView, 0, 0).y;
        root.same("selected-row-visible", top >= 0 && top + selected.height <= core.resultsView.height, true);
        Settings.data.appLauncher.viewMode = "grid";
        core.selectedIndex = 0;
        break;
      case 7:
        root.moveTo(1, 0);
        break;
      case 8:
        root.moveTo(2, 0);
        break;
      case 9:
        root.same("grid-pointer-selects", core.selectedIndex, 2);
        // The agreed grid-sideways command is Shift+Tab; Left edits search.
        keyboard.command = ["python3", "-B", Quickshell.env("LAUNCHER_INPUT_HELPER"), "key", "42:1", "15:1", "15:0", "42:0"];
        keyboard.running = true;
        break;
      case 10:
        root.same("grid-one-highlight", root.rows().filter(item => item.isSelected).map(item => item.index), [1]);
        console.log("LAUNCHER_SELECTION_DONE");
        Qt.exit(root.failed ? 1 : 0);
      }
    }
  }
}
