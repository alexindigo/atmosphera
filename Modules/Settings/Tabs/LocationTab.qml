import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

  NHeader {
    label: I18n.tr("settings.location.location.section.label")
    description: I18n.tr("settings.location.location.section.description")
  }

  // Location section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginL

    NTextInput {
      label: I18n.tr("settings.location.location.search.label")
      description: I18n.tr("settings.location.location.search.description")
      text: Settings.data.location.name || Settings.defaultLocation
      placeholderText: I18n.tr("settings.location.location.search.placeholder")
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
      Layout.maximumWidth: 420
    }

    NText {
      visible: LocationService.coordinatesReady
      text: I18n.tr("system.location-display", {
                      "name": LocationService.stableName,
                      "coordinates": LocationService.displayCoordinates
                    })
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignRight
      Layout.alignment: Qt.AlignBottom
      Layout.bottomMargin: Style.marginM
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Weather section
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.location.weather.section.label")
      description: I18n.tr("settings.location.weather.section.description")
    }

    NToggle {
      label: I18n.tr("settings.location.weather.enabled.label")
      description: I18n.tr("settings.location.weather.enabled.description")
      checked: Settings.data.location.weatherEnabled
      onToggled: checked => Settings.data.location.weatherEnabled = checked
    }

    NToggle {
      label: I18n.tr("settings.location.weather.fahrenheit.label")
      description: I18n.tr("settings.location.weather.fahrenheit.description")
      checked: Settings.data.location.useFahrenheit
      onToggled: checked => Settings.data.location.useFahrenheit = checked
      enabled: Settings.data.location.weatherEnabled
      opacity: Settings.data.location.weatherEnabled ? 1.0 : 0.5
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }

  // Date & time section
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.location.date-time.section.label")
      description: I18n.tr("settings.location.date-time.section.description")
    }

    NToggle {
      label: I18n.tr("settings.location.date-time.12hour-format.label")
      description: I18n.tr("settings.location.date-time.12hour-format.description")
      checked: Settings.data.location.use12hourFormat
      onToggled: checked => Settings.data.location.use12hourFormat = checked
    }

    NToggle {
      label: I18n.tr("settings.location.date-time.week-numbers.label")
      description: I18n.tr("settings.location.date-time.week-numbers.description")
      checked: Settings.data.location.showWeekNumberInCalendar
      onToggled: checked => Settings.data.location.showWeekNumberInCalendar = checked
    }

    NComboBox {
      label: I18n.tr("settings.location.date-time.first-day-of-week.label")
      description: I18n.tr("settings.location.date-time.first-day-of-week.description")
      minimumWidth: 220 * Style.uiScaleRatio
      model: [{
          "key": "auto",
          "name": I18n.tr("settings.location.date-time.first-day-of-week.auto")
        }, {
          "key": "monday",
          "name": I18n.tr("settings.location.date-time.first-day-of-week.monday")
        }, {
          "key": "saturday",
          "name": I18n.tr("settings.location.date-time.first-day-of-week.saturday")
        }, {
          "key": "sunday",
          "name": I18n.tr("settings.location.date-time.first-day-of-week.sunday")
        }]
      currentKey: Settings.data.location.firstDayOfWeek
      onSelected: key => Settings.data.location.firstDayOfWeek = key
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }
}
