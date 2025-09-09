pragma Singleton

import Quickshell
import Quickshell.Services.UPower
import qs.Services

Singleton {
  id: root

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return Bootstrap.icons["battery_empty"] // FIXME: find battery error ?
    }

    if (charging) {
      return Bootstrap.icons["battery_charging"]
    } else {
      if (percent >= 85)
        return Bootstrap.icons["battery_full"]
      if (percent >= 45)
        return Bootstrap.icons["battery_half"]
      if (percent >= 25)
        return Bootstrap.icons["battery_low"]
      if (percent >= 0)
        return Bootstrap.icons["battery_empty"]
    }
  }
}
