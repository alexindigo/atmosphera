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
    icon: NightLightService.isActive ? "bedtime" : "bedtime_off"
    iconCircleColor: NightLightService.isActive ? Color.mSecondary : Color.mOnSurfaceVariant
    collapsedIconColor: NightLightService.isActive ? Color.mOnSecondary : Color.mOnSurface
    autoHide: false
    text: NightLightService.isActive ? "On" : "Off"
    tooltipText: {
      if (!Settings.isLoaded || !Settings.data.nightLight.enabled) {
        return "Night Light: Disabled\nLeft click to open settings.\nRight click to enable."
      }

      var status = NightLightService.isActive ? "Active" : "Inactive (outside schedule)"
      var intensity = Math.round(Settings.data.nightLight.intensity * 100)
      var schedule = Settings.data.nightLight.autoSchedule ? `Schedule: ${Settings.data.nightLight.startTime} - ${Settings.data.nightLight.stopTime}` : "Manual mode"

      return `Intensity: ${intensity}%\n${schedule}\nLeft click to open settings.\nRight click to toggle.`
    }

    onClicked: {
      // Left click - open settings
      var settingsPanel = PanelService.getPanel("settingsPanel")
      settingsPanel.requestedTab = SettingsPanel.Tab.Display
      settingsPanel.open(screen)
    }

    onRightClicked: {
      // Right click - toggle night light
      Settings.data.nightLight.enabled = !Settings.data.nightLight.enabled
    }

    onWheel: delta => {
               var diff = delta > 0 ? 0.05 : -0.05
               Settings.data.nightLight.intensity = Math.max(0, Math.min(1.0,
                                                                         Settings.data.nightLight.intensity + diff))
             }
  }
}
