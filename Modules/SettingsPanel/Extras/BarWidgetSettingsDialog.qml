import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

// Widget Settings Dialog Component
Popup {
  id: settingsPopup

  property int widgetIndex: -1
  property var widgetData: null
  property string widgetId: ""

  // Center popup in parent
  x: (parent.width - width) * 0.5
  y: (parent.height - height) * 0.5

  width: 420 * scaling
  height: content.implicitHeight + padding * 2
  padding: Style.marginXL * scaling
  modal: true

  background: Rectangle {
    id: bgRect
    color: Color.mSurface
    radius: Style.radiusL * scaling
    border.color: Color.mPrimary
    border.width: Style.borderM * scaling
  }

  ColumnLayout {
    id: content
    width: parent.width
    spacing: Style.marginM * scaling

    // Title
    RowLayout {
      Layout.fillWidth: true

      NText {
        text: "Widget Settings: " + settingsPopup.widgetId
        font.pointSize: Style.fontSizeL * scaling
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "close"
        onClicked: settingsPopup.close()
      }
    }

    // Separator
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Color.mOutline
    }

    // Settings based on widget type
    Loader {
      id: settingsLoader
      Layout.fillWidth: true
      sourceComponent: {
        if (settingsPopup.widgetId === "CustomButton") {
          return customButtonSettings
        } else if (settingsPopup.widgetId === "Spacer") {
          return spacerSettings
        } else if (settingsPopup.widgetId === "Workspace") {
          return workspaceSettings
        } else if (settingsPopup.widgetId === "SystemMonitor") {
          return systemMonitorSettings
        } else if (settingsPopup.widgetId === "ActiveWindow") {
          return activeWindowSettings
        } else if (settingsPopup.widgetId === "MediaMini") {
          return mediaMiniSettings
        } else if (settingsPopup.widgetId === "Clock") {
          return clockSettings
        } else if (settingsPopup.widgetId === "Volume") {
          return volumeSettings
        } else if (settingsPopup.widgetId === "Microphone") {
          return microphoneSettings
        } else if (settingsPopup.widgetId === "NotificationHistory") {
          return notificationHistorySettings
        } else if (settingsPopup.widgetId === "Brightness") {
          return brightnessSettings
        } else if (settingsPopup.widgetId === "SidePanelToggle") {
          return sidePanelToggleSettings
        }
        // Add more widget settings components here as needed
        return null
      }
    }

    // Action buttons
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM * scaling

      Item {
        Layout.fillWidth: true
      }

      NButton {
        text: "Cancel"
        outlined: true
        onClicked: settingsPopup.close()
      }

      NButton {
        text: "Apply"
        icon: "check"
        onClicked: {
          if (settingsLoader.item && settingsLoader.item.saveSettings) {
            var newSettings = settingsLoader.item.saveSettings()
            root.updateWidgetSettings(sectionId, settingsPopup.widgetIndex, newSettings)
            settingsPopup.close()
          }
        }
      }
    }
  }

  // SidePanelToggle settings component
  Component {
    id: sidePanelToggleSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueUseDistroLogo: settingsPopup.widgetData.useDistroLogo
                                        !== undefined ? settingsPopup.widgetData.useDistroLogo : BarWidgetRegistry.widgetMetadata["SidePanelToggle"].useDistroLogo

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.useDistroLogo = valueUseDistroLogo
        return settings
      }

      NCheckbox {
        label: "Use distro logo instead of icon"
        checked: valueUseDistroLogo
        onToggled: checked => valueUseDistroLogo = checked
      }
    }
  }

  // Brightness settings component
  Component {
    id: brightnessSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueAlwaysShowPercentage: settingsPopup.widgetData.alwaysShowPercentage
                                               !== undefined ? settingsPopup.widgetData.alwaysShowPercentage : BarWidgetRegistry.widgetMetadata["Brightness"].alwaysShowPercentage

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.alwaysShowPercentage = valueAlwaysShowPercentage
        return settings
      }

      NCheckbox {
        label: "Always show percentage"
        checked: valueAlwaysShowPercentage
        onToggled: checked => valueAlwaysShowPercentage = checked
      }
    }
  }

  // NotificationHistory settings component
  Component {
    id: notificationHistorySettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueShowUnreadBadge: settingsPopup.widgetData.showUnreadBadge
                                          !== undefined ? settingsPopup.widgetData.showUnreadBadge : BarWidgetRegistry.widgetMetadata["NotificationHistory"].showUnreadBadge
      property bool valueHideWhenZero: settingsPopup.widgetData.hideWhenZero
                                       !== undefined ? settingsPopup.widgetData.hideWhenZero : BarWidgetRegistry.widgetMetadata["NotificationHistory"].hideWhenZero

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.showUnreadBadge = valueShowUnreadBadge
        settings.hideWhenZero = valueHideWhenZero
        return settings
      }

      NCheckbox {
        label: "Show unread badge"
        checked: valueShowUnreadBadge
        onToggled: checked => valueShowUnreadBadge = checked
      }

      NCheckbox {
        label: "Hide badge when zero"
        checked: valueHideWhenZero
        onToggled: checked => valueHideWhenZero = checked
      }
    }
  }

  // Microphone settings component
  Component {
    id: microphoneSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueAlwaysShowPercentage: settingsPopup.widgetData.alwaysShowPercentage
                                               !== undefined ? settingsPopup.widgetData.alwaysShowPercentage : BarWidgetRegistry.widgetMetadata["Microphone"].alwaysShowPercentage

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.alwaysShowPercentage = valueAlwaysShowPercentage
        return settings
      }

      NCheckbox {
        label: "Always show percentage"
        checked: valueAlwaysShowPercentage
        onToggled: checked => valueAlwaysShowPercentage = checked
      }
    }
  }

  // Volume settings component
  Component {
    id: volumeSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueAlwaysShowPercentage: settingsPopup.widgetData.alwaysShowPercentage
                                               !== undefined ? settingsPopup.widgetData.alwaysShowPercentage : BarWidgetRegistry.widgetMetadata["Volume"].alwaysShowPercentage

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.alwaysShowPercentage = valueAlwaysShowPercentage
        return settings
      }

      NCheckbox {
        label: "Always show percentage"
        checked: valueAlwaysShowPercentage
        onToggled: checked => valueAlwaysShowPercentage = checked
      }
    }
  }

  // Clock settings component
  Component {
    id: clockSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueShowDate: settingsPopup.widgetData.showDate
                                   !== undefined ? settingsPopup.widgetData.showDate : BarWidgetRegistry.widgetMetadata["Clock"].showDate
      property bool valueUse12h: settingsPopup.widgetData.use12HourClock
                                 !== undefined ? settingsPopup.widgetData.use12HourClock : BarWidgetRegistry.widgetMetadata["Clock"].use12HourClock
      property bool valueShowSeconds: settingsPopup.widgetData.showSeconds
                                      !== undefined ? settingsPopup.widgetData.showSeconds : BarWidgetRegistry.widgetMetadata["Clock"].showSeconds

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.showDate = valueShowDate
        settings.use12HourClock = valueUse12h
        settings.showSeconds = valueShowSeconds
        return settings
      }

      NCheckbox {
        label: "Show date next to time"
        checked: valueShowDate
        onToggled: checked => valueShowDate = checked
      }

      NCheckbox {
        label: "Use 12-hour clock"
        checked: valueUse12h
        onToggled: checked => valueUse12h = checked
      }

      NCheckbox {
        label: "Show seconds"
        checked: valueShowSeconds
        onToggled: checked => valueShowSeconds = checked
      }
    }
  }

  // MediaMini settings component
  Component {
    id: mediaMiniSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local state
      property bool valueShowAlbumArt: settingsPopup.widgetData.showAlbumArt
                                       !== undefined ? settingsPopup.widgetData.showAlbumArt : BarWidgetRegistry.widgetMetadata["MediaMini"].showAlbumArt
      property bool valueShowVisualizer: settingsPopup.widgetData.showVisualizer
                                         !== undefined ? settingsPopup.widgetData.showVisualizer : BarWidgetRegistry.widgetMetadata["MediaMini"].showVisualizer
      property string valueVisualizerType: settingsPopup.widgetData.visualizerType
                                           || BarWidgetRegistry.widgetMetadata["MediaMini"].visualizerType

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.showAlbumArt = valueShowAlbumArt
        settings.showVisualizer = valueShowVisualizer
        settings.visualizerType = valueVisualizerType
        return settings
      }

      NCheckbox {
        label: "Show album art"
        checked: valueShowAlbumArt
        onToggled: checked => valueShowAlbumArt = checked
      }

      NCheckbox {
        label: "Show visualizer"
        checked: valueShowVisualizer
        onToggled: checked => valueShowVisualizer = checked
      }

      NComboBox {
        label: "Visualizer type"
        description: "Select the visualizer style"
        preferredWidth: 180 * scaling
        model: ListModel {
          ListElement {
            key: "linear"
            name: "Linear"
          }
          ListElement {
            key: "mirrored"
            name: "Mirrored"
          }
          ListElement {
            key: "wave"
            name: "Wave"
          }
        }
        currentKey: valueVisualizerType
        onSelected: key => valueVisualizerType = key
      }
    }
  }

  // ActiveWindow settings component
  Component {
    id: activeWindowSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local, editable state
      property bool valueShowIcon: settingsPopup.widgetData.showIcon
                                   !== undefined ? settingsPopup.widgetData.showIcon : BarWidgetRegistry.widgetMetadata["ActiveWindow"].showIcon

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.showIcon = valueShowIcon
        return settings
      }

      NCheckbox {
        id: showIcon
        Layout.fillWidth: true
        label: "Show app icon"
        checked: valueShowIcon
        onToggled: checked => valueShowIcon = checked
      }
    }
  }

  // CustomButton settings component
  Component {
    id: customButtonSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.icon = iconInput.text
        settings.leftClickExec = leftClickExecInput.text
        settings.rightClickExec = rightClickExecInput.text
        settings.middleClickExec = middleClickExecInput.text
        return settings
      }

      // Icon setting
      NTextInput {
        id: iconInput
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginXL * scaling
        label: "Icon Name"
        description: "Use Material Icon names from the icon set."
        text: settingsPopup.widgetData.icon || ""
        placeholderText: "Enter icon name (e.g., favorite, home, settings)"
      }

      NTextInput {
        id: leftClickExecInput
        Layout.fillWidth: true
        label: "Left Click Command"
        description: "Command or application to run when left clicked."
        text: settingsPopup.widgetData.leftClickExec || ""
        placeholderText: "Enter command to execute (app or custom script)"
      }

      NTextInput {
        id: rightClickExecInput
        Layout.fillWidth: true
        label: "Right Click Command"
        description: "Command or application to run when right clicked."
        text: settingsPopup.widgetData.rightClickExec || ""
        placeholderText: "Enter command to execute (app or custom script)"
      }

      NTextInput {
        id: middleClickExecInput
        Layout.fillWidth: true
        label: "Middle Click Command"
        description: "Command or application to run when middle clicked."
        text: settingsPopup.widgetData.middleClickExec || ""
        placeholderText: "Enter command to execute (app or custom script)"
      }
    }
  }

  // Spacer settings component
  Component {
    id: spacerSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.width = parseInt(widthInput.text) || 20
        return settings
      }

      NTextInput {
        id: widthInput
        Layout.fillWidth: true
        label: "Width (pixels)"
        description: "Width of the spacer in pixels."
        text: settingsPopup.widgetData.width || "20"
        placeholderText: "Enter width in pixels"
      }
    }
  }

  // Workspace settings component
  Component {
    id: workspaceSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.labelMode = labelModeCombo.currentKey
        return settings
      }

      NComboBox {
        id: labelModeCombo
        Layout.fillWidth: true
        preferredWidth: 180 * scaling
        label: "Label Mode"
        description: "Choose how to label workspace pills."
        model: ListModel {
          ListElement {
            key: "none"
            name: "None"
          }
          ListElement {
            key: "index"
            name: "Index"
          }
          ListElement {
            key: "name"
            name: "Name"
          }
        }
        currentKey: settingsPopup.widgetData.labelMode || BarWidgetRegistry.widgetMetadata["Workspace"].labelMode
        onSelected: key => labelModeCombo.currentKey = key
      }
    }
  }

  // SystemMonitor settings component
  Component {
    id: systemMonitorSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      // Local, editable state for checkboxes
      property bool valueShowCpuUsage: settingsPopup.widgetData.showCpuUsage
                                       !== undefined ? settingsPopup.widgetData.showCpuUsage : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showCpuUsage
      property bool valueShowCpuTemp: settingsPopup.widgetData.showCpuTemp
                                      !== undefined ? settingsPopup.widgetData.showCpuTemp : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showCpuTemp
      property bool valueShowMemoryUsage: settingsPopup.widgetData.showMemoryUsage
                                          !== undefined ? settingsPopup.widgetData.showMemoryUsage : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showMemoryUsage
      property bool valueShowNetworkStats: settingsPopup.widgetData.showNetworkStats
                                           !== undefined ? settingsPopup.widgetData.showNetworkStats : BarWidgetRegistry.widgetMetadata["SystemMonitor"].showNetworkStats

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.showCpuUsage = valueShowCpuUsage
        settings.showCpuTemp = valueShowCpuTemp
        settings.showMemoryUsage = valueShowMemoryUsage
        settings.showNetworkStats = valueShowNetworkStats
        return settings
      }

      NCheckbox {
        id: showCpuUsage
        Layout.fillWidth: true
        label: "CPU usage"
        checked: valueShowCpuUsage
        onToggled: checked => valueShowCpuUsage = checked
      }

      NCheckbox {
        id: showCpuTemp
        Layout.fillWidth: true
        label: "CPU temperature"
        checked: valueShowCpuTemp
        onToggled: checked => valueShowCpuTemp = checked
      }

      NCheckbox {
        id: showMemoryUsage
        Layout.fillWidth: true
        label: "Memory usage"
        checked: valueShowMemoryUsage
        onToggled: checked => valueShowMemoryUsage = checked
      }

      NCheckbox {
        id: showNetworkStats
        Layout.fillWidth: true
        label: "Network traffic"
        checked: valueShowNetworkStats
        onToggled: checked => valueShowNetworkStats = checked
      }
    }
  }
}
