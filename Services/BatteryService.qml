pragma Singleton

import Quickshell
import Quickshell.Services.UPower

Singleton {
  id: root

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "battery_error"
    }

    if (charging) {
      if (percent >= 95)
        return "battery_full"
      if (percent >= 85)
        return "battery_charging_90"
      if (percent >= 65)
        return "battery_charging_80"
      if (percent >= 55)
        return "battery_charging_60"
      if (percent >= 45)
        return "battery_charging_50"
      if (percent >= 25)
        return "battery_charging_30"
      if (percent >= 0)
        return "battery_charging_20"
    } else {
      if (percent >= 95)
        return "battery_full"
      if (percent >= 85)
        return "battery_6_bar"
      if (percent >= 70)
        return "battery_5_bar"
      if (percent >= 55)
        return "battery_4_bar"
      if (percent >= 40)
        return "battery_3_bar"
      if (percent >= 25)
        return "battery_2_bar"
      if (percent >= 10)
        return "battery_1_bar"
      if (percent >= 0)
        return "battery_0_bar"
    }
  }
}
