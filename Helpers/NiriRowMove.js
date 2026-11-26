.pragma library

// A workspace's tiled layout, in compositor order. Fail closed on partial
// or duplicate ordinals rather than deriving actions from a torn update.
function columnsFor(windows, workspaceId) {
  const columns = [];
  const tiles = windows.filter(w => w.workspaceId === workspaceId && !w.isFloating && w.layout.posInScrollingLayout.length === 2);
  for (const w of tiles) {
    const [column, row] = w.layout.posInScrollingLayout;
    if (column > tiles.length || row > tiles.length)
      return null;
    const entries = columns[column - 1] ?? (columns[column - 1] = []);
    if (entries[row - 1] !== undefined)
      return null;
    entries[row - 1] = w.id;
  }
  return Array.from(columns).every(col => col && Array.from(col).every(id => id !== undefined)) ? columns : null;
}

function locate(columns, id) {
  const column = columns.findIndex(col => col.includes(id));
  return column === -1 ? null : [column, columns[column].indexOf(id)];
}

function sameLayout(a, b) {
  return a !== null && b !== null && JSON.stringify(a) === JSON.stringify(b);
}

function withoutWindow(columns, column, row) {
  const next = columns.map(col => col.slice());
  next[column].splice(row, 1);
  if (next[column].length === 0)
    next.splice(column, 1);
  return next;
}

function destination(columns, windowId, target) {
  const source = columns && locate(columns, windowId);
  if (!source || target.anchorId === windowId)
    return null;
  const final = withoutWindow(columns, ...source);
  const anchor = locate(final, target.anchorId);
  if (target.kind === "gap" && (target.anchorId === null || anchor)) {
    final.splice(anchor ? anchor[0] + 1 : 0, 0, [windowId]);
  } else if (target.kind === "stack" && anchor && Number.isSafeInteger(target.index) && target.index >= 1 && target.index <= final[anchor[0]].length + 1) {
    final[anchor[0]].splice(target.index - 1, 0, windowId);
  } else {
    return null;
  }
  return final;
}

// Return one action and the exact postcondition to verify before proceeding.
// All indices here are zero-based; only moveColumn's IPC argument converts.
function nextStep(columns, focusedId, windowId, target, final) {
  const [col, row] = locate(columns, windowId);
  const [finalCol, finalRow] = locate(final, windowId);
  const targetCol = target.kind === "stack" ? locate(columns, target.anchorId)[0] : -1;
  const stacked = columns[col].length > 1;
  const focus = {action: "focus", columns, focusedId: windowId};
  const next = columns.map(c => c.slice());
  function result(action, index) {
    return {action, columns: next, focusedId, index};
  }
  function shift(direction) {
    next[col].splice(row, 1);
    if (stacked) {
      next.splice(col + (direction > 0 ? 1 : 0), 0, [windowId]);
    } else {
      next[col + direction].push(windowId);
      next.splice(col, 1);
    }
    return result(direction < 0 ? "left" : "right");
  }
  function moveColumn(index) {
    if (focusedId !== windowId)
      return focus;
    next.splice(index, 0, next.splice(col, 1)[0]);
    return result("column", index + 1);
  }

  if (sameLayout(columns, final))
    return focusedId === windowId ? null : focus;
  if (target.kind === "gap")
    return stacked ? shift(finalCol <= col ? -1 : 1) : moveColumn(finalCol);
  if (col === targetCol) {
    if (focusedId !== windowId)
      return focus;
    const swap = row + Math.sign(finalRow - row);
    [next[col][row], next[col][swap]] = [next[col][swap], next[col][row]];
    return result(swap < row ? "up" : "down");
  }

  // The focus-based consume shortcut takes precisely the top tile of the
  // active column's right neighbor. Use it only when no setup focus is needed.
  if (stacked && row === 0 && targetCol === col - 1 && columns[targetCol].includes(focusedId)) {
    next[col].shift();
    next[targetCol].push(windowId);
    return result("consume");
  }
  if (stacked || Math.abs(col - targetCol) === 1)
    return shift(Math.sign(targetCol - col));
  const withoutSource = withoutWindow(columns, col, row);
  return moveColumn(locate(withoutSource, target.anchorId)[0] + 1);
}
