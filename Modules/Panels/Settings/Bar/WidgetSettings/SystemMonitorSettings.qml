import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local, editable state for checkboxes
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueShowCpuUsage: widgetData.showCpuUsage !== undefined ? widgetData.showCpuUsage : widgetMetadata.showCpuUsage
  property bool valueShowCpuTemp: widgetData.showCpuTemp !== undefined ? widgetData.showCpuTemp : widgetMetadata.showCpuTemp
  property bool valueShowMemoryUsage: widgetData.showMemoryUsage !== undefined ? widgetData.showMemoryUsage : widgetMetadata.showMemoryUsage
  property bool valueShowMemoryAsPercent: widgetData.showMemoryAsPercent !== undefined ? widgetData.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  property bool valueShowNetworkStats: widgetData.showNetworkStats !== undefined ? widgetData.showNetworkStats : widgetMetadata.showNetworkStats
  property bool valueShowDiskUsage: widgetData.showDiskUsage !== undefined ? widgetData.showDiskUsage : widgetMetadata.showDiskUsage

  // Threshold settings
  property int valueCpuWarningThreshold: widgetData.cpuWarningThreshold !== undefined ? widgetData.cpuWarningThreshold : widgetMetadata.cpuWarningThreshold
  property int valueCpuCriticalThreshold: widgetData.cpuCriticalThreshold !== undefined ? widgetData.cpuCriticalThreshold : widgetMetadata.cpuCriticalThreshold
  property int valueTempWarningThreshold: widgetData.tempWarningThreshold !== undefined ? widgetData.tempWarningThreshold : widgetMetadata.tempWarningThreshold
  property int valueTempCriticalThreshold: widgetData.tempCriticalThreshold !== undefined ? widgetData.tempCriticalThreshold : widgetMetadata.tempCriticalThreshold
  property int valueMemWarningThreshold: widgetData.memWarningThreshold !== undefined ? widgetData.memWarningThreshold : widgetMetadata.memWarningThreshold
  property int valueMemCriticalThreshold: widgetData.memCriticalThreshold !== undefined ? widgetData.memCriticalThreshold : widgetMetadata.memCriticalThreshold
  property int valueDiskWarningThreshold: widgetData.diskWarningThreshold !== undefined ? widgetData.diskWarningThreshold : widgetMetadata.diskWarningThreshold
  property int valueDiskCriticalThreshold: widgetData.diskCriticalThreshold !== undefined ? widgetData.diskCriticalThreshold : widgetMetadata.diskCriticalThreshold

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.usePrimaryColor = valueUsePrimaryColor
    settings.showCpuUsage = valueShowCpuUsage
    settings.showCpuTemp = valueShowCpuTemp
    settings.showMemoryUsage = valueShowMemoryUsage
    settings.showMemoryAsPercent = valueShowMemoryAsPercent
    settings.showNetworkStats = valueShowNetworkStats
    settings.showDiskUsage = valueShowDiskUsage
    settings.cpuWarningThreshold = valueCpuWarningThreshold
    settings.cpuCriticalThreshold = valueCpuCriticalThreshold
    settings.tempWarningThreshold = valueTempWarningThreshold
    settings.tempCriticalThreshold = valueTempCriticalThreshold
    settings.memWarningThreshold = valueMemWarningThreshold
    settings.memCriticalThreshold = valueMemCriticalThreshold
    settings.diskWarningThreshold = valueDiskWarningThreshold
    settings.diskCriticalThreshold = valueDiskCriticalThreshold
    // Ensure critical thresholds are not less than their warning counterparts.
    if (settings.cpuCriticalThreshold < settings.cpuWarningThreshold) {
      settings.cpuCriticalThreshold = Math.min(100, settings.cpuWarningThreshold)
    }
    if (settings.tempCriticalThreshold < settings.tempWarningThreshold) {
      settings.tempCriticalThreshold = Math.min(100, settings.tempWarningThreshold)
    }
    if (settings.memCriticalThreshold < settings.memWarningThreshold) {
      settings.memCriticalThreshold = Math.min(100, settings.memWarningThreshold)
    }
    if (settings.diskCriticalThreshold < settings.diskWarningThreshold) {
      settings.diskCriticalThreshold = Math.min(100, settings.diskWarningThreshold)
    }

    return settings
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.clock.use-primary-color.label")
    description: I18n.tr("bar.widget-settings.clock.use-primary-color.description")
    checked: valueUsePrimaryColor
    onToggled: checked => valueUsePrimaryColor = checked
  }

  NToggle {
    id: showCpuUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.cpu-usage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.cpu-usage.description")
    checked: valueShowCpuUsage
    onToggled: checked => valueShowCpuUsage = checked
  }

  NToggle {
    id: showCpuTemp
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.cpu-temperature.label")
    description: I18n.tr("bar.widget-settings.system-monitor.cpu-temperature.description")
    checked: valueShowCpuTemp
    onToggled: checked => valueShowCpuTemp = checked
  }

  NToggle {
    id: showMemoryUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.memory-usage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.memory-usage.description")
    checked: valueShowMemoryUsage
    onToggled: checked => valueShowMemoryUsage = checked
  }

  NToggle {
    id: showMemoryAsPercent
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.memory-percentage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.memory-percentage.description")
    checked: valueShowMemoryAsPercent
    onToggled: checked => valueShowMemoryAsPercent = checked
    visible: valueShowMemoryUsage
  }

  NToggle {
    id: showNetworkStats
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.network-traffic.label")
    description: I18n.tr("bar.widget-settings.system-monitor.network-traffic.description")
    checked: valueShowNetworkStats
    onToggled: checked => valueShowNetworkStats = checked
  }

  NToggle {
    id: showDiskUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.storage-usage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.storage-usage.description")
    checked: valueShowDiskUsage
    onToggled: checked => valueShowDiskUsage = checked
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NHeader {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.thresholds.header")
    description: I18n.tr("bar.widget-settings.system-monitor.thresholds.description")
  }

  // CPU Usage Thresholds
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: valueShowCpuUsage

    // Warning threshold
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.cpu-warning-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueCpuWarningThreshold
        onValueChanged: valueCpuWarningThreshold = value
        suffix: "%"
      }
    }

    // Critical threshold
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.cpu-critical-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueCpuCriticalThreshold
        onValueChanged: valueCpuCriticalThreshold = value
        suffix: "%"
      }
    }
  }

  // Temperature Thresholds
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: valueShowCpuTemp

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.temp-warning-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueTempWarningThreshold
        onValueChanged: valueTempWarningThreshold = value
        suffix: "°C"
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.temp-critical-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueTempCriticalThreshold
        onValueChanged: valueTempCriticalThreshold = value
        suffix: "°C"
      }
    }
  }

  // Memory Usage Thresholds
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: valueShowMemoryUsage

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.mem-warning-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueMemWarningThreshold
        onValueChanged: valueMemWarningThreshold = value
        suffix: "%"
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.mem-critical-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueMemCriticalThreshold
        onValueChanged: valueMemCriticalThreshold = value
        suffix: "%"
      }
    }
  }

  // Storage Space Thresholds
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: valueShowDiskUsage

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.disk-warning-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueDiskWarningThreshold
        onValueChanged: valueDiskWarningThreshold = value
        suffix: "%"
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: I18n.tr("bar.widget-settings.system-monitor.disk-critical-threshold.label")
        pointSize: Style.fontSizeS
        Layout.alignment: Qt.AlignVCenter
      }

      NSpinBox {
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: valueDiskCriticalThreshold
        onValueChanged: valueDiskCriticalThreshold = value
        suffix: "%"
      }
    }
  }
}
