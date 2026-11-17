// Authoritative niri snapshots in; a directional target or a proven bound out.
// Width/viewport clipping is deliberately not a focus-navigation capability.
function resolve(output, edge, workspaces, windows) {
  var vertical = edge === "top" || edge === "bottom";
  if (!vertical && edge !== "left" && edge !== "right")
    return {kind: "unknown"};
  var ordered = workspaces.filter(function (ws) { return ws.output === output; }).sort(function (a, b) { return a.idx - b.idx; });
  // niri numbers complete output/workspace column lists from one. A gap is
  // incomplete topology, not evidence that the first visible record is a wall.
  if (ordered.some(function (ws, index) { return ws.idx !== index + 1; }))
    return {kind: "unknown"};
  var active = ordered.filter(function (ws) { return ws.isActive; });
  if (active.length !== 1 || !active[0].isFocused)
    return {kind: "unknown"};
  var workspace = active[0];
  var result = {kind: "unknown", output: output, edge: edge, workspaceId: workspace.id};
  var local = windows.filter(function (win) { return win.workspaceId === workspace.id; });
  var focused = local.find(function (win) { return win.id === workspace.activeWindowId; });
  if (vertical) {
    var index = ordered.findIndex(function (ws) { return ws.id === workspace.id; });
    var next = index + (edge === "top" ? -1 : 1);
    result.kind = next < 0 || next >= ordered.length ? "boundary" : "navigate";
    if (result.kind === "boundary" && focused && focused.isFloating)
      result.kind = "unknown";
    if (result.kind === "navigate")
      result.targetWorkspaceId = ordered[next].id;
    return result;
  }
  // Floating layout has different directional semantics. Do not infer a wall
  // from its absent column index, even when tiled columns exist underneath it.
  if (!focused || focused.isFloating) {
    if (local.length === 0 && !workspace.activeWindowId)
      result.kind = "boundary";
    return result;
  }
  var tiled = local.filter(function (win) { return !win.isFloating; });
  function column(win) { return win.layout.posInScrollingLayout[0]; }
  if (tiled.some(function (win) { return !win.layout || !win.layout.posInScrollingLayout || !Number.isInteger(column(win)) || column(win) < 1; }))
    return result;
  var columns = Array.from(new Set(tiled.map(column))).sort(function (a, b) { return a - b; });
  if (columns.some(function (col, index) { return col !== index + 1; }))
    return result;
  var current = column(focused);
  var nextColumn = columns.indexOf(current) + (edge === "left" ? -1 : 1);
  result.windowId = focused.id;
  result.column = current;
  result.kind = nextColumn < 0 || nextColumn >= columns.length ? "boundary" : "navigate";
  if (result.kind === "navigate")
    result.targetColumn = columns[nextColumn];
  return result;
}

function outcome(before, afterWorkspaces, afterWindows) {
  var after = resolve(before.output, before.edge, afterWorkspaces, afterWindows);
  if (before.targetWorkspaceId !== undefined)
    return after.workspaceId === before.targetWorkspaceId ? "moved" : "unknown";
  if (after.workspaceId !== before.workspaceId || after.column === undefined)
    return "unknown";
  if (after.column === before.targetColumn && after.windowId !== before.windowId)
    return "moved";
  // A disappearing target can turn an action into a no-op. Only authoritative
  // bounds in the unchanged active column establish a wall; silence cannot.
  return after.windowId === before.windowId && after.column === before.column && after.kind === "boundary" ? "boundary" : "unknown";
}
