import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Hardware
import qs.Services.Power
import qs.Services.System
import qs.Widgets
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("panels.hardware-health.title")
    description: I18n.tr("panels.hardware-health.description")
    Layout.fillWidth: true
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.hardware-health.thermal-warnings-label")
    description: I18n.tr("panels.hardware-health.thermal-warnings-description")
    checked: Settings.data.hardwareHealth.thermalWarnings
    defaultValue: Settings.getDefaultValue("hardwareHealth.thermalWarnings")
    onToggled: checked => Settings.data.hardwareHealth.thermalWarnings = checked
  }

  NSpinBox {
    Layout.alignment: Qt.AlignHCenter
    from: 5
    to: 30
    stepSize: 1
    value: Settings.data.hardwareHealth.warnOffsetC
    defaultValue: Settings.getDefaultValue("hardwareHealth.warnOffsetC")
    suffix: "°C"
    enabled: Settings.data.hardwareHealth.thermalWarnings
    visible: enabled
    onValueChanged: Settings.data.hardwareHealth.warnOffsetC = value
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.hardware-health.unclean-notice-label")
    description: I18n.tr("panels.hardware-health.unclean-notice-description")
    checked: Settings.data.hardwareHealth.uncleanShutdownNotice
    defaultValue: Settings.getDefaultValue("hardwareHealth.uncleanShutdownNotice")
    onToggled: checked => Settings.data.hardwareHealth.uncleanShutdownNotice = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.hardware-health.history-log-label")
    description: I18n.tr("panels.hardware-health.history-log-description")
    checked: Settings.data.hardwareHealth.enableHistoryLog
    defaultValue: Settings.getDefaultValue("hardwareHealth.enableHistoryLog")
    onToggled: checked => Settings.data.hardwareHealth.enableHistoryLog = checked
  }

  NComboBox {
    Layout.fillWidth: true
    visible: PowerProfileService.available
    label: I18n.tr("panels.hardware-health.power-profile-label")
    description: I18n.tr("panels.hardware-health.power-profile-description")
    model: [
      {
        "key": "powersaver",
        "name": PowerProfileService.getName(PowerProfile.PowerSaver)
      },
      {
        "key": "balanced",
        "name": PowerProfileService.getName(PowerProfile.Balanced)
      },
      {
        "key": "performance",
        "name": PowerProfileService.getName(PowerProfile.Performance)
      }
    ]
    currentKey: {
      switch (PowerProfileService.profile) {
      case PowerProfile.PowerSaver:
        return "powersaver";
      case PowerProfile.Performance:
        return "performance";
      default:
        return "balanced";
      }
    }
    onSelected: key => {
      if (key === "powersaver") {
        PowerProfileService.setProfile(PowerProfile.PowerSaver);
      } else if (key === "performance") {
        PowerProfileService.setProfile(PowerProfile.Performance);
      } else {
        PowerProfileService.setProfile(PowerProfile.Balanced);
      }
    }
  }

  // Turbo boost toggle (via app.atmosphera.HwController helper; display-only
  // when the helper isn't installed, hidden when the platform has no knob)
  NToggle {
    Layout.fillWidth: true
    visible: TurboService.available
    label: I18n.tr("panels.hardware-health.turbo-label")
    description: TurboService.helperAvailable ? I18n.tr("panels.hardware-health.turbo-description") : I18n.tr("panels.hardware-health.turbo-helper-missing")
    checked: TurboService.turboEnabled
    enabled: TurboService.helperAvailable
    onToggled: checked => TurboService.setTurboEnabled(checked)
  }

  // Live sensor readings (when the machine exposes them)
  NBox {
    Layout.fillWidth: true
    visible: SystemStatService.sensors.length > 0 || SystemStatService.fans.length > 0
    implicitHeight: sensorsCol.implicitHeight + Style.margin2L
    color: Color.mSurface
    clip: true

    ColumnLayout {
      id: sensorsCol
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginXS

      NText {
        text: I18n.tr("panels.hardware-health.sensors-title")
        font.weight: Style.fontWeightSemiBold
      }

      Repeater {
        model: SystemStatService.sensors
        delegate: RowLayout {
          Layout.fillWidth: true
          required property var modelData
          NText {
            Layout.fillWidth: true
            text: (modelData.label || modelData.chip)
            color: Color.mOnSurface
            elide: Text.ElideRight
          }
          NText {
            text: modelData.temp + " °C" + (modelData.crit > 0 ? "  /  " + I18n.tr("panels.hardware-health.sensor-crit") + " " + modelData.crit + " °C" : "")
            color: modelData.crit > 0 && modelData.temp >= modelData.crit - Settings.data.hardwareHealth.warnOffsetC ? Color.mError : Color.mOutline
          }
        }
      }

      Repeater {
        model: SystemStatService.fans
        delegate: RowLayout {
          Layout.fillWidth: true
          required property var modelData
          NText {
            Layout.fillWidth: true
            text: modelData.label || modelData.chip
            color: Color.mOnSurface
            elide: Text.ElideRight
          }
          NText {
            text: modelData.rpm + " RPM"
            color: Color.mOutline
          }
        }
      }
    }
  }
}
