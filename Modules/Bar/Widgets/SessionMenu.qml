import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string colorName: widgetSettings.colorName !== undefined ? widgetSettings.colorName : widgetMetadata.colorName

  readonly property color iconColor: {
    switch (colorName) {
    case "primary":
      return Color.mPrimary
    case "secondary":
      return Color.mSecondary
    case "tertiary":
      return Color.mTertiary
    case "error":
      return Color.mError
    case "onSurface":
    default:
      return Color.mOnSurface
    }
  }

  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  icon: "power"
  tooltipText: I18n.tr("tooltips.session-menu")
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: root.iconColor
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: PanelService.getPanel("sessionMenuPanel", screen)?.toggle()
}
