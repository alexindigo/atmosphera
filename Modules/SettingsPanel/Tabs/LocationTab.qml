import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL * scaling

  NHeader {
    label: "Your Location"
    description: "Set your location for weather, time zones, and scheduling."
  }

  // Location section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginL * scaling

    NTextInput {
      label: "Location name"
      description: "Choose a known location near you."
      text: Settings.data.location.name || Settings.defaultLocation
      placeholderText: "Enter the location name"
      onEditingFinished: {
        // Verify the location has really changed to avoid extra resets
        var newLocation = text.trim()
        // If empty, set to default location
        if (newLocation === "") {
          newLocation = Settings.defaultLocation
          text = Settings.defaultLocation // Update the input field to show the default
        }
        if (newLocation != Settings.data.location.name) {
          Settings.data.location.name = newLocation
          LocationService.resetWeather()
        }
      }
      Layout.maximumWidth: 420 * scaling
    }

    NText {
      visible: LocationService.coordinatesReady
      text: `${LocationService.stableName} (${LocationService.displayCoordinates})`
      font.pointSize: Style.fontSizeS * scaling
      color: Color.mOnSurfaceVariant
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignRight
      Layout.alignment: Qt.AlignBottom
      Layout.bottomMargin: 12 * scaling
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Weather section
  ColumnLayout {
    spacing: Style.marginM * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Weather"
      description: "Configure temperature units."
    }

    NToggle {
      label: "Use Fahrenheit"
      description: "Display temperature in Fahrenheit instead of Celsius."
      checked: Settings.data.location.useFahrenheit
      onToggled: checked => Settings.data.location.useFahrenheit = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Weather section
  ColumnLayout {
    spacing: Style.marginM * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Time & Date"
      description: "Configure time and date formats."
    }

    NToggle {
      label: "Use 12-hour time format"
      description: "Classic AM/PM or modern 24-hour."
      checked: Settings.data.location.use12hourFormat
      onToggled: checked => Settings.data.location.use12hourFormat = checked
    }

    NToggle {
      label: "Show month before day"
      description: "Organize your dates. On for 09/17/2025, off for 17/09/2025."
      checked: Settings.data.location.monthBeforeDay
      onToggled: checked => Settings.data.location.monthBeforeDay = checked
    }

    NToggle {
      label: "Show week number in calendar"
      description: "Displays the week number of the year in calendar view."
      checked: Settings.data.location.showWeekNumberInCalendar
      onToggled: checked => Settings.data.location.showWeekNumberInCalendar = checked
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }
}
