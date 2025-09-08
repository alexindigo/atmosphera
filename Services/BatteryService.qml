pragma Singleton

import Quickshell
import Quickshell.Services.UPower
import qs.Services

Singleton {
  id: root

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return FontService.icons["battery_empty"] // FIXME: find battery error ?
    }

    if (charging) {
      return FontService.icons["battery_charging"]
    } else {
      if (percent >= 85)
        return FontService.icons["battery_full"]
      if (percent >= 45)
        return FontService.icons["battery_half"]
      if (percent >= 25)
        return FontService.icons["battery_low"]
      if (percent >= 0)
        return FontService.icons["battery_empty"]
    }
  }
}
