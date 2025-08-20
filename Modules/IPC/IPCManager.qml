import QtQuick
import Quickshell.Io
import qs.Services

Item {
  id: root

  IpcHandler {
    target: "settings"

    function toggle() {
      settingsPanel.isLoaded = !settingsPanel.isLoaded
    }
  }

  IpcHandler {
    target: "notifications"

    function toggleHistory() {
      notificationHistoryPanel.isLoaded = !notificationHistoryPanel.isLoaded
    }

    function toggleDoNotDisturb() {// TODO
    }
  }

  IpcHandler {
    target: "idleInhibitor"

    function toggle() {
      return IdleInhibitorService.manualToggle()
    }
  }

  IpcHandler {
    target: "appLauncher"

    function toggle() {
      appLauncherPanel.isLoaded = !appLauncherPanel.isLoaded
    }
  }

  IpcHandler {
    target: "lockScreen"

    function toggle() {
      // Only lock if not already locked (prevents the red screen issue)
      // Note: No unlock via IPC for security reasons
      if (!lockScreen.isLoaded) {
        lockScreen.isLoaded = true
      }
    }
  }

  IpcHandler {
    target: "brightness"

    function increase() {
      BrightnessService.increaseBrightness()
    }

    function decrease() {
      BrightnessService.decreaseBrightness()
    }
  }
}
