import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.SettingsPanel
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  implicitWidth: pill.width
  implicitHeight: pill.height
  visible: true

  NPill {
    id: pill
    icon: Settings.data.nightLight.enabled ? "bedtime" : "bedtime_off"
    iconCircleColor: Settings.data.nightLight.enabled ? Color.mSecondary : Color.mOnSurfaceVariant
    collapsedIconColor: Settings.data.nightLight.enabled ? Color.mOnSecondary : Color.mOnSurface
    autoHide: false
    text: Settings.data.nightLight.enabled ? "On" : "Off"
    tooltipText: {
      if (!Settings.isLoaded || !Settings.data.nightLight.enabled) {
        return "Night Light: Disabled\nLeft click to open settings.\nRight click to enable."
      }

      var intensity = Math.round(Settings.data.nightLight.intensity * 100)
      var schedule = Settings.data.nightLight.autoSchedule ? `Auto schedule` : `Manual: ${Settings.data.nightLight.startTime} - ${Settings.data.nightLight.stopTime}`
      return `Night Light: Enabled\nIntensity: ${intensity}%\n${schedule}\nLeft click to open settings.\nRight click to toggle.`
    }

    onClicked: {
      // Left click - open settings
      var settingsPanel = PanelService.getPanel("settingsPanel")
      settingsPanel.requestedTab = SettingsPanel.Tab.Display
      settingsPanel.open(screen)
    }

    onRightClicked: {
      // Right click - toggle night light (debounced apply handled by service)
      Settings.data.nightLight.enabled = !Settings.data.nightLight.enabled
      NightLightService.apply()
    }

    // Wheel handler removed to avoid frequent rapid restarts/flicker
  }
}
