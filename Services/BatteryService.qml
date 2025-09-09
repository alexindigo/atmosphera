pragma Singleton

import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Services

Singleton {
  id: root

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "exclamation-diamond"
    }

    if (charging) {
      return "battery-charging"
    } else {
      if (percent >= 85)
        return "battery-full"
      if (percent >= 45)
        return "battery-half"
      if (percent >= 25)
        return "battery-low"
      if (percent >= 0)
        return "battery"
    }
  }
}
