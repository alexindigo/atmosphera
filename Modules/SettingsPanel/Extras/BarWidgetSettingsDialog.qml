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

  width: 400 * scaling
  height: content.implicitHeight + padding * 2
  padding: Style.marginL * scaling
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
        colorBg: Color.transparent
        colorFg: Color.mOnSurface
        colorBgHover: Color.applyOpacity(Color.mError, "20")
        colorFgHover: Color.mError
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
        text: "Save"
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

  // CustomButton settings component
  Component {
    id: customButtonSettings

    ColumnLayout {
      spacing: Style.marginM * scaling

      property alias iconField: iconInput
      property alias executeField: executeInput

      function saveSettings() {
        var settings = Object.assign({}, settingsPopup.widgetData)
        settings.icon = iconInput.text
        settings.execute = executeInput.text
        return settings
      }

      // Icon setting
      NTextInput {
        id: iconInput
        Layout.fillWidth: true
        label: "Icon Name"
        description: "Use Material Icon names from the icon set"
        text: settingsPopup.widgetData.icon || ""
        placeholderText: "Enter icon name (e.g., favorite, home, settings)"
      }

      // Execute command setting
      NTextInput {
        id: executeInput
        Layout.fillWidth: true
        label: "Execute Command"
        description: "Command or application to run when clicked"
        text: settingsPopup.widgetData.execute || ""
        placeholderText: "Enter command to execute (app or custom script)"
      }
    }
  }
}
