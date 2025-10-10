pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services

Singleton {
  id: root

  enum ChargingMode {
    Disabled = 0,
    Full,
    Balanced,
    Lifespan
  }

  property int chargingMode: Settings.data.battery.chargingMode
  readonly property string batterySetterScript: Quickshell.shellDir + '/Bin/battery-manager/set-battery-treshold.sh'
  readonly property string batteryInstallerScript: Quickshell.shellDir + '/Bin/battery-manager/install-battery-manager.sh'

  // This is false when setter is started in init so that a toast isn't shown on every startup
  property bool hideSuccessToast: true

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

  function getThresholdValue(chargingMode) {
    switch (chargingMode) {
    case BatteryService.ChargingMode.Full:
      return "100"
    case BatteryService.ChargingMode.Balanced:
      return "80"
    case BatteryService.ChargingMode.Lifespan:
      return "60"
    }
  }

  function setChargingMode(newMode) {
    if (newMode !== BatteryService.ChargingMode.Full && newMode !== BatteryService.ChargingMode.Balanced && newMode !== BatteryService.ChargingMode.Lifespan) {
      return
    }
    BatteryService.chargingMode = newMode
    BatteryService.applyChargingMode()
  }

  function applyChargingMode(hideToast = false) {
    let command = [batterySetterScript]

    // Currently the script sends notifications by default but quickshell
    // uses toast messages so the flag is passed to supress notifs
    command.push("-q")

    command.push(BatteryService.getThresholdValue(BatteryService.chargingMode))
    BatteryService.hideSuccessToast = hideToast

    setterProcess.command = command
    setterProcess.running = true
  }

  function runInstaller() {
    installerProcess.command = ["pkexec", batteryInstallerScript]
    installerProcess.running = true
  }

  function init() {
    if (BatteryService.chargingMode !== BatteryService.ChargingMode.Disabled) {
      BatteryService.applyChargingMode(true)
      Logger.log("BatteryService", `Applied charging mode - ${BatteryService.chargingMode}`)
    }
  }

  Process {
    id: setterProcess
    workingDirectory: Quickshell.shellDir
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        Logger.log("BatteryService", "Battery threshold set successfully")
        if (!BatteryService.hideSuccessToast) {
          ToastService.showNotice("Battery Manager", `Battery threshold set to ${BatteryService.getThresholdValue(BatteryService.chargingMode)}%`)
          Settings.data.battery.chargingMode = BatteryService.chargingMode
        }
      } else if (exitCode === 2) {
        // Initial setup required - show toast and run installer
        ToastService.showWarning("Battery Manager", "Initial setup required")
        BatteryService.runInstaller()
      } else {
        ToastService.showError("Battery Manager", "Failed to set battery threshold")
        Logger.error("BatteryService", `Setter process failed with exit code: ${exitCode}`)
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "SetterProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "SetterProcess stdout:", this.text)
        }
      }
    }
  }

  // Installer process - installs battery manager components
  Process {
    id: installerProcess
    workingDirectory: Quickshell.shellDir
    running: false
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        ToastService.showNotice("Battery Manager", "Installed successfully")
        // Installation successful, retry setting the battery threshold
        BatteryService.applyChargingMode()
      } else if (exitCode === 2) {
        ToastService.showError("Battery Manager", "Required files are missing")
      } else if (exitCode === 3) {
        ToastService.showError("Battery Manager", "System is not supported")
      } else {
        ToastService.showError("Battery Manager", "Installation failed")
      }

      if (exitCode !== 0) {
        BatteryService.chargingMode = BatteryService.ChargingMode.Disabled
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.warn("BatteryService", "InstallerProcess stderr:", this.text)
        }
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.log("BatteryService", "InstallerProcess stdout:", this.text)
        }
      }
    }
  }
}
