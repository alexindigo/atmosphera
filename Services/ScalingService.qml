pragma Singleton

import Quickshell
import qs.Commons

Singleton {
  id: root

  // Automatic, orientation-agnostic scaling
  function scale(aScreen) {
    return scaleByName(aScreen.name)
  }

  function scaleByName(aScreenName) {
    try {
      if (Settings.data.monitorsScaling !== undefined) {
        if (Settings.data.monitorsScaling[aScreenName] !== undefined) {
          return Settings.data.monitorsScaling[aScreenName]
        }
      }
    } catch (e) {
      Logger.warn(e)
    }

    return 1.0
  }
}
