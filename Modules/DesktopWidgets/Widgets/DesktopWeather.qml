import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Location
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)
  readonly property int currentWeatherCode: weatherReady ? LocationService.data.weather.current_weather.weathercode : 0
  readonly property real currentTemp: {
    if (!weatherReady)
      return 0;
    var temp = LocationService.data.weather.current_weather.temperature;
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property real todayMax: {
    if (!weatherReady || !LocationService.data.weather.daily || LocationService.data.weather.daily.temperature_2m_max.length === 0)
      return 0;
    var temp = LocationService.data.weather.daily.temperature_2m_max[0];
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property real todayMin: {
    if (!weatherReady || !LocationService.data.weather.daily || LocationService.data.weather.daily.temperature_2m_min.length === 0)
      return 0;
    var temp = LocationService.data.weather.daily.temperature_2m_min[0];
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property string tempUnit: Settings.data.location.useFahrenheit ? "F" : "C"
  readonly property string locationName: {
    const chunks = Settings.data.location.name.split(",");
    return chunks[0];
  }

  implicitWidth: Math.max(240 * Style.uiScaleRatio, contentLayout.implicitWidth + Style.marginM * 2)
  implicitHeight: 64 * Style.uiScaleRatio + Style.marginM * 2
  width: implicitWidth
  height: implicitHeight

  RowLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM
    z: 2

    Item {
      Layout.preferredWidth: 64 * Style.uiScaleRatio
      Layout.preferredHeight: 64 * Style.uiScaleRatio
      Layout.alignment: Qt.AlignVCenter

      NIcon {
        anchors.centerIn: parent
        icon: weatherReady ? LocationService.weatherSymbolFromCode(currentWeatherCode) : "cloud"
        pointSize: Style.fontSizeXXXL * 2
        color: weatherReady ? Color.mPrimary : Color.mOnSurfaceVariant
      }
    }

    NText {
      text: weatherReady ? `${currentTemp}°${tempUnit}` : "---"
      pointSize: Style.fontSizeXXXL
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXXS
      Layout.alignment: Qt.AlignVCenter

      NText {
        Layout.fillWidth: true
        text: locationName || "No location"
        pointSize: Style.fontSizeS
        font.weight: Style.fontWeightRegular
        color: Color.mOnSurfaceVariant
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      RowLayout {
        spacing: Style.marginXS
        visible: weatherReady && todayMax > 0 && todayMin > 0

        NText {
          text: "H:"
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
        NText {
          text: `${todayMax}°`
          pointSize: Style.fontSizeXS
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurface
        }

        NText {
          text: "•"
          pointSize: Style.fontSizeXXS
          color: Color.mOnSurfaceVariant
          opacity: 0.5
        }

        NText {
          text: "L:"
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
        NText {
          text: `${todayMin}°`
          pointSize: Style.fontSizeXS
          font.weight: Style.fontWeightMedium
          color: Color.mOnSurfaceVariant
        }
      }
    }
  }
}
