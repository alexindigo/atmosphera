pragma Singleton

import Quickshell
import qs.Commons

Singleton {
  id: root

  // -------------------------------------------
  // Manual scaling via Settings
  function scale(aScreen) {
    try {
      if (aScreen !== undefined && aScreen.name !== undefined) {
        return getMonitorScale(aScreen.name)
      }
    } catch (e) {

      //Logger.warn(e)
    }
    return 1.0
  }

  // -------------------------------------------
  function getMonitorScale(aScreenName) {
    try {
      var monitors = Settings.data.ui.monitorsScaling
      if (monitors !== undefined) {
        for (var i = 0; i < monitors.length; i++) {
          if (monitors[i].name !== undefined && monitors[i].name === aScreenName) {
            return monitors[i].scale
          }
        }
      }
    } catch (e) {

      //Logger.warn(e)
    }
    return 1.0
  }

  // -------------------------------------------
  function setMonitorScale(aScreenName, scale) {
    try {
      var monitors = Settings.data.ui.monitorsScaling
      if (monitors !== undefined) {
        for (var i = 0; i < monitors.length; i++) {
          if (monitors[i].name !== undefined && monitors[i].name === aScreenName) {
            monitors[i].scale = scale
            return
          }
        }
      }
      monitors.push({
                      "name": aScreenName,
                      "scale": scale
                    })
    } catch (e) {

      //Logger.warn(e)
    }
  }

  // -------------------------------------------
  // Dynamic scaling based on resolution

  // Design reference resolution (for scale = 1.0)
  readonly property int designScreenWidth: 2560
  readonly property int designScreenHeight: 1440

  function dynamicScale(aScreen) {
    if (aScreen != null) {
      var ratioW = aScreen.width / designScreenWidth
      var ratioH = aScreen.height / designScreenHeight
      return Math.min(ratioW, ratioH)
    }
    return 1.0
  }
}
