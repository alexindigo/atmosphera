pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Bar position property - initialize safely
  property string position: "top"

  // Signal emitted when bar position changes
  signal barPositionChanged(string newPosition)

  // Watch for changes in Settings.data.bar.position
  Connections {
    target: Settings
    function onDataChanged() {
      if (Settings.data && Settings.data.bar && Settings.data.bar.position !== root.position) {
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
    if (Settings.data && Settings.data.bar) {
      Settings.data.bar.position = newPosition
    }
  }

  // Initialize position after component is completed
  Component.onCompleted: {
    if (Settings.data && Settings.data.bar) {
      position = Settings.data.bar.position
    }
  }
}
