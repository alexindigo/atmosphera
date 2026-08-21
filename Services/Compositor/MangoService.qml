import QtQuick

// MangoService — inert stub for upstream Quickshell compatibility.
// Quickshell.DWL is a noctalia-qs extension not available upstream.
// This preserves the public interface so CompositorService's Component
// can resolve the type without the DWL module.
Item {
  // ===== PUBLIC INTERFACE (CompositorService compatibility) =====

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1
  property bool initialized: false

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  // ===== MANGOSERVICE-SPECIFIC PROPERTIES =====

  property string selectedMonitor: ""
  property string currentLayoutSymbol: ""
}
