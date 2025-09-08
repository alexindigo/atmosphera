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
        text: `${settingsPopup.widgetId} Settings`
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

      source: {
        const widgetSettingsMap = {
          "ActiveWindow": "WidgetSettings/ActiveWindowSettings.qml",
          "Battery": "WidgetSettings/BatterySettings.qml",
          "Brightness": "WidgetSettings/BrightnessSettings.qml",
          "Clock": "WidgetSettings/ClockSettings.qml",
          "CustomButton": "WidgetSettings/CustomButtonSettings.qml",
          "MediaMini": "WidgetSettings/MediaMiniSettings.qml",
          "Microphone": "WidgetSettings/MicrophoneSettings.qml",
          "NotificationHistory": "WidgetSettings/NotificationHistorySettings.qml",
          "Workspace": "WidgetSettings/WorkspaceSettings.qml",
          "SidePanelToggle": "WidgetSettings/SidePanelToggleSettings.qml",
          "Spacer": "WidgetSettings/SpacerSettings.qml",
          "SystemMonitor": "WidgetSettings/SystemMonitorSettings.qml",
          "Volume": "WidgetSettings/VolumeSettings.qml"
        }
        return widgetSettingsMap[settingsPopup.widgetId] || ""
      }

      onLoaded: {
        if (item) {
          // Pass data to the loaded component
          item.widgetData = settingsPopup.widgetData
          item.widgetMetadata = BarWidgetRegistry.widgetMetadata[settingsPopup.widgetId]
        }
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
}
