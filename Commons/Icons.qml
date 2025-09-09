pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons.IconsSets

Singleton {
  id: root

  // Expose the font family name for easy access
  readonly property string fontFamily: fontLoader.name
  readonly property string defaultIcon: Bootstrap.defaultIcon

  Component.onCompleted: {
    Logger.log("Icons", "Service started")
  }

  function get(iconName) {
    return Bootstrap.icons[iconName]
  }

  FontLoader {
    id: fontLoader
    source: Quickshell.shellDir + "/Assets/Fonts/bootstrap/bootstrap-icons.woff2"
  }

  // Monitor font loading status
  Connections {
    target: fontLoader
    function onStatusChanged() {
      if (fontLoader.status === FontLoader.Ready) {
        Logger.log("Bootstrap", "Font loaded successfully:", fontFamily)
      } else if (fontLoader.status === FontLoader.Error) {
        Logger.error("Bootstrap", "Font failed to load")
      }
    }
  }
}
