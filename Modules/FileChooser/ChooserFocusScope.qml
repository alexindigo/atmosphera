import QtQuick
import qs.Widgets

// Modal chooser surfaces cycle only through their own visible controls. Native
// focus, not a second accessible cursor, remains the source of AT-SPI focus.
FocusScope {
  id: root
  function cycleFocus(forward) {
    var start = root.Window.window ? root.Window.window.activeFocusItem : root;
    var candidate = start || root;
    var visited = [];
    while (candidate && !visited.includes(candidate)) {
      visited.push(candidate);
      candidate = candidate.nextItemInFocusChain(forward);
      if (!candidate) break;
      var owner = candidate.parent;
      while (owner && owner !== root) owner = owner.parent;
      if (owner === root && candidate.visible && candidate.enabled && candidate.width > 0 && candidate.height > 0) {
        candidate.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        return;
      }
    }
    root.forceActiveFocus();
  }
  // Controls consume native Tab traversal before bubbling Keys to an ancestor.
  // Use the same live-surface shortcuts as the other modal chooser actions.
  NScopedShortcut { scope: root; sequence: "Tab"; onActivated: root.cycleFocus(true) }
  NScopedShortcut { scope: root; sequence: "Shift+Tab"; onActivated: root.cycleFocus(false) }
}
