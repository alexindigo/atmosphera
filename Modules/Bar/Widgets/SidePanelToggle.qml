import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Effects
import qs.Commons
import qs.Widgets
import qs.Services

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: 1.0
  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

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

  readonly property bool userUseDistroLogo: (widgetSettings.useDistroLogo !== undefined) ? widgetSettings.useDistroLogo : ((Settings.data.bar.useDistroLogo !== undefined) ? Settings.data.bar.useDistroLogo : BarWidgetRegistry.widgetMetadata["SidePanelToggle"].useDistroLogo)

  icon: userUseDistroLogo ? "" : "widgets"
  tooltipText: "Open side panel."
  sizeRatio: 0.8

  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  anchors.verticalCenter: parent.verticalCenter
  onClicked: PanelService.getPanel("sidePanel")?.toggle(screen, this)
  onRightClicked: PanelService.getPanel("settingsPanel")?.toggle(screen)

  IconImage {
    id: logo
    anchors.centerIn: parent
    width: root.width * 0.6
    height: width
    source: userUseDistroLogo ? DistroLogoService.osLogo : ""
    visible: userUseDistroLogo && source !== ""
    smooth: true
  }

  MultiEffect {
    anchors.fill: logo
    source: logo
    //visible: logo.visible
    colorization: 1
    brightness: 1
    saturation: 1
    colorizationColor: root.hovering ? Color.mSurfaceVariant : Color.mOnSurface
  }
}
