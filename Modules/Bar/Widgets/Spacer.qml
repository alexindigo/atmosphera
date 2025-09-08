import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  // Widget properties passed from Bar.qml
  property var screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    var section = barSection.replace("Section", "").toLowerCase()
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  // Use settings or defaults from BarWidgetRegistry
  readonly property int spacerWidth: widgetSettings.width !== undefined ? widgetSettings.width : widgetMetadata.width

  // Set the width based on user settings
  implicitWidth: spacerWidth * scaling
  implicitHeight: Style.barHeight * scaling
  width: implicitWidth
  height: implicitHeight

  // Optional: Add a subtle visual indicator in debug mode
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(1, 0, 0, 0.1) // Very subtle red tint
    visible: Settings.data.general.debugMode || false
    radius: Style.radiusXXS * scaling
  }
}
