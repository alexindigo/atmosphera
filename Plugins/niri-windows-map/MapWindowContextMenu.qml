import QtQuick
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

NPopupContextMenu {
  id: root
  property var windowData: null

  // Emitted when a menu action navigates (Focus) — NOT for Close
  signal navigationRequested

  model: [
    { id: "focus", text: "Focus", icon: Icon.apps },
    { id: "close", text: "Close", icon: Icon.close }
  ]

  onTriggered: function (actionId, _item) {
    if (!root.windowData) return
    switch (actionId) {
    case "focus":
      CompositorService.focusWindow({ id: root.windowData.id })
      root.navigationRequested()
      break
    case "close":
      CompositorService.niriBackend.closeWindow({ id: root.windowData.id })
      break
    }
  }
}
