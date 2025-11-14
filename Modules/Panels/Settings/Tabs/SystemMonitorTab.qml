import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  NHeader {
    Layout.fillWidth: true
    label: I18n.tr("settings.system-monitor.general.section.label")
    description: I18n.tr("settings.system-monitor.general.section.description")
  }

  // CPU Usage Thresholds
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.cpu-section.label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.cpu-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.cpuWarningThreshold
        onValueChanged: {
          Settings.data.systemMonitor.cpuWarningThreshold = value
          // Ensure critical >= warning
          if (Settings.data.systemMonitor.cpuCriticalThreshold < value) {
            Settings.data.systemMonitor.cpuCriticalThreshold = value
          }
        }
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.cpu-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: Settings.data.systemMonitor.cpuWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.cpuCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.cpuCriticalThreshold = value
        suffix: "%"
      }
    }
  }

  // Temperature Thresholds
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.temperature-section.label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.temp-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.tempWarningThreshold
        onValueChanged: {
          Settings.data.systemMonitor.tempWarningThreshold = value
          if (Settings.data.systemMonitor.tempCriticalThreshold < value) {
            Settings.data.systemMonitor.tempCriticalThreshold = value
          }
        }
        suffix: "°C"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.temp-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: Settings.data.systemMonitor.tempWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.tempCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.tempCriticalThreshold = value
        suffix: "°C"
      }
    }
  }

  // Memory Usage Thresholds
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.memory-section.label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.mem-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.memWarningThreshold
        onValueChanged: {
          Settings.data.systemMonitor.memWarningThreshold = value
          if (Settings.data.systemMonitor.memCriticalThreshold < value) {
            Settings.data.systemMonitor.memCriticalThreshold = value
          }
        }
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.mem-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: Settings.data.systemMonitor.memWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.memCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.memCriticalThreshold = value
        suffix: "%"
      }
    }
  }

  // Disk Usage Thresholds
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.disk-section.label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.disk-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.diskWarningThreshold
        onValueChanged: {
          Settings.data.systemMonitor.diskWarningThreshold = value
          if (Settings.data.systemMonitor.diskCriticalThreshold < value) {
            Settings.data.systemMonitor.diskCriticalThreshold = value
          }
        }
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.disk-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        from: Settings.data.systemMonitor.diskWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.diskCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.diskCriticalThreshold = value
        suffix: "%"
      }
    }
  }
}
