import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services
import "./WidgetSettings" as WidgetSettings

// Widget Settings Dialog Component
Popup {
  // Don't replace by root!
  id: widgetSettings

  property int widgetIndex: -1
  property var widgetData: null
  property string widgetId: ""

  property bool isMasked: false

  // Center popup in parent
  x: (parent.width - width) * 0.5
  y: (parent.height - height) * 0.5

  width: Math.max(content.implicitWidth + padding * 2, 500 * scaling)
  height: content.implicitHeight + padding * 2
  padding: Style.marginXL * scaling
  modal: true

  onOpened: {
    // Mark this popup has opened in the PanelService
    PanelService.willOpenPopup(widgetSettings)

    // Load settings when popup opens with data
    if (widgetData && widgetId) {
      loadWidgetSettings()
    }
  }

  onClosed: {
    PanelService.willClosePopup(widgetSettings)
  }

  background: Rectangle {
    id: bgRect

    opacity: widgetSettings.isMasked ? 0 : 1.0
    color: Color.mSurface
    radius: Style.radiusL * scaling
    border.color: Color.mPrimary
    border.width: Math.max(1, Style.borderM * scaling)
  }

  contentItem: ColumnLayout {
    id: content

    opacity: widgetSettings.isMasked ? 0 : 1.0
    width: parent.width
    spacing: Style.marginM * scaling

    // Title
    RowLayout {
      Layout.fillWidth: true

      NText {
        text: `${widgetSettings.widgetId} Settings`
        font.pointSize: Style.fontSizeL * scaling
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "close"
        onClicked: widgetSettings.close()
      }
    }

    // Separator
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Color.mOutline
    }

    // Settings based on widget type
    // Will be triggered via settingsLoader.setSource()
    Loader {
      id: settingsLoader
      Layout.fillWidth: true
    }

    // Action buttons
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM * scaling
      spacing: Style.marginM * scaling

      Item {
        Layout.fillWidth: true
      }

      NButton {
        text: "Cancel"
        outlined: true
        onClicked: widgetSettings.close()
      }

      NButton {
        text: "Apply"
        icon: "check"
        onClicked: {
          if (settingsLoader.item && settingsLoader.item.saveSettings) {
            var newSettings = settingsLoader.item.saveSettings()
            root.updateWidgetSettings(sectionId, widgetSettings.widgetIndex, newSettings)
            widgetSettings.close()
          }
        }
      }
    }
  }

  function loadWidgetSettings() {
    const widgetSettingsMap = {
      "ActiveWindow": "WidgetSettings/ActiveWindowSettings.qml",
      "Battery": "WidgetSettings/BatterySettings.qml",
      "Brightness": "WidgetSettings/BrightnessSettings.qml",
      "Clock": "WidgetSettings/ClockSettings.qml",
      "CustomButton": "WidgetSettings/CustomButtonSettings.qml",
      "KeyboardLayout": "WidgetSettings/KeyboardLayoutSettings.qml",
      "MediaMini": "WidgetSettings/MediaMiniSettings.qml",
      "Microphone": "WidgetSettings/MicrophoneSettings.qml",
      "NotificationHistory": "WidgetSettings/NotificationHistorySettings.qml",
      "Workspace": "WidgetSettings/WorkspaceSettings.qml",
      "SidePanelToggle": "WidgetSettings/SidePanelToggleSettings.qml",
      "Spacer": "WidgetSettings/SpacerSettings.qml",
      "SystemMonitor": "WidgetSettings/SystemMonitorSettings.qml",
      "Volume": "WidgetSettings/VolumeSettings.qml"
    }

    const source = widgetSettingsMap[widgetId]
    if (source) {
      // Use setSource to pass properties at creation time
      settingsLoader.setSource(source, {
                                 "widgetData": widgetData,
                                 "widgetMetadata": BarWidgetRegistry.widgetMetadata[widgetId]
                               })
    }
  }
}
