pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Bar position property
  property string position: Settings.data.bar.position

  // Signal emitted when bar position changes
  signal barPositionChanged(string newPosition)

  // Watch for changes in Settings.data.bar.position
  Connections {
    target: Settings
    function onDataChanged() {
      if (Settings.data.bar.position !== root.position) {
        root.position = Settings.data.bar.position
        root.barPositionChanged(root.position)
      }
    }
  }

  // Also watch for direct changes to the position property
  onPositionChanged: {
    root.barPositionChanged(position)
  }

  // Function to change bar position
  function setPosition(newPosition) {
    Settings.data.bar.position = newPosition
  }
}
