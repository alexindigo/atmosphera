pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services

Singleton {
  id: root

  enum ChargingMode {
    Full,
    Balanced,
    Conservative
  }

  property int chargingMode: BatteryService.ChargingMode.Balanced
  readonly property string batteryTresholdScript: Quickshell.shellDir + '/Bin/battery-manager/set-battery-treshold.sh'

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "battery-exclamation"
    }

    if (charging) {
      return "battery-charging"
    } else {
      if (percent >= 90)
        return "battery-4"
      if (percent >= 50)
        return "battery-3"
      if (percent >= 25)
        return "battery-2"
      if (percent >= 0)
        return "battery-1"
      return "battery"
    }
  }

  function setChargingMode(newMode) {
    switch (newMode) {
    case BatteryService.ChargingMode.Full:
      BatteryService.chargingMode = newMode
      chargeLimitProcess.command = [batteryTresholdScript, "100"]
      break
    case BatteryService.ChargingMode.Balanced:
      BatteryService.chargingMode = newMode
      chargeLimitProcess.command = [batteryTresholdScript, "80"]
      break
    case BatteryService.ChargingMode.Conservative:
      BatteryService.chargingMode = newMode
      chargeLimitProcess.command = [batteryTresholdScript, "60"]
      break
    default:
      return
    }
    chargeLimitProcess.running = true
  }

  Process {
    id: chargeLimitProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "ChargeLimitProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "ChargeLimitProcess stdout:", this.text)
        }
      }
    }
  }
}
