import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Services.Location
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property var widgetData: null
  property int widgetIndex: -1

  property bool isDragging: false
  property real dragOffsetX: 0
  property real dragOffsetY: 0

  readonly property bool weatherReady: Settings.data.location.weatherEnabled && (LocationService.data.weather !== null)
  readonly property int currentWeatherCode: weatherReady ? LocationService.data.weather.current_weather.weathercode : 0
  readonly property real currentTemp: {
    if (!weatherReady) return 0;
    var temp = LocationService.data.weather.current_weather.temperature;
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property real todayMax: {
    if (!weatherReady || !LocationService.data.weather.daily || LocationService.data.weather.daily.temperature_2m_max.length === 0) return 0;
    var temp = LocationService.data.weather.daily.temperature_2m_max[0];
    if (Settings.data.location.useFahrenheit) {
      temp = LocationService.celsiusToFahrenheit(temp);
    }
    return Math.round(temp);
  }
  readonly property real todayMin: {
    if (!weatherReady || !LocationService.data.weather.daily || LocationService.data.weather.daily.temperature_2m_min.length === 0) return 0;
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

  x: isDragging ? dragOffsetX : ((widgetData && widgetData.x !== undefined) ? widgetData.x : 100)
  y: isDragging ? dragOffsetY : ((widgetData && widgetData.y !== undefined) ? widgetData.y : 100)

  property color textColor: Color.mOnSurface
  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.marginS
    color: Settings.data.desktopWidgets.editMode ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1) : "transparent"
    border.color: (Settings.data.desktopWidgets.editMode || isDragging) ? (isDragging ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5) : Color.mPrimary) : "transparent"
    border.width: Settings.data.desktopWidgets.editMode ? 3 : (isDragging ? 2 : 0)
    radius: Style.radiusL + Style.marginS
    z: -1
  }

  Rectangle {
    id: container
    anchors.fill: parent
    radius: Style.radiusL
    color: Color.mSurface
    border {
      width: 1
      color: Qt.alpha(Color.mOutline, 0.12)
    }
    clip: true
    visible: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

    layer.enabled: Settings.data.general.enableShadows && !root.isDragging && ((widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true)
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowBlur: Style.shadowBlur * 1.5
      shadowOpacity: Style.shadowOpacity * 0.6
      shadowColor: Color.black
      shadowHorizontalOffset: Settings.data.general.shadowOffsetX
      shadowVerticalOffset: Settings.data.general.shadowOffsetY
      blurMax: Style.shadowBlurMax
    }
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    z: 1
    enabled: Settings.data.desktopWidgets.editMode
    cursorShape: enabled && isDragging ? Qt.ClosedHandCursor : (enabled ? Qt.OpenHandCursor : Qt.ArrowCursor)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    propagateComposedEvents: true
    
    property point pressPos: Qt.point(0, 0)
    property bool isDraggingWidget: false

    onPressed: mouse => {
      pressPos = Qt.point(mouse.x, mouse.y);
      dragOffsetX = root.x;
      dragOffsetY = root.y;
      isDragging = true;
      isDraggingWidget = true;
    }

    onPositionChanged: mouse => {
      if (isDragging && isDraggingWidget && pressed) {
        var globalPos = mapToItem(root.parent, mouse.x, mouse.y);
        var newX = globalPos.x - pressPos.x;
        var newY = globalPos.y - pressPos.y;
        
        if (root.parent && root.width > 0 && root.height > 0) {
          newX = Math.max(0, Math.min(newX, root.parent.width - root.width));
          newY = Math.max(0, Math.min(newY, root.parent.height - root.height));
        }
        
        if (root.parent && root.parent.checkCollision && root.parent.checkCollision(root, newX, newY)) {
          return;
        }
        
        dragOffsetX = newX;
        dragOffsetY = newY;
      }
    }

    onReleased: mouse => {
      if (isDragging && widgetIndex >= 0) {
        var widgets = Settings.data.desktopWidgets.widgets.slice();
        if (widgetIndex < widgets.length) {
          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], {
            "x": dragOffsetX,
            "y": dragOffsetY
          });
          Settings.data.desktopWidgets.widgets = widgets;
        }
        isDragging = false;
        isDraggingWidget = false;
      }
    }

    onCanceled: {
      isDragging = false;
      isDraggingWidget = false;
    }
  }

  RowLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM

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

