import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings
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
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string iconName: widgetSettings.icon || (widgetMetadata ? widgetMetadata.icon : "search")
  readonly property bool usePrimaryColor: (widgetSettings.usePrimaryColor !== undefined) ? widgetSettings.usePrimaryColor : ((widgetMetadata && widgetMetadata.usePrimaryColor !== undefined) ? widgetMetadata.usePrimaryColor : true)

  icon: iconName
  tooltipText: I18n.tr("context-menu.open-launcher")
  tooltipDirection: BarService.getTooltipDirection()
  baseSize: Style.capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorBgHover: Color.mHover
  colorFg: usePrimaryColor ? Color.mPrimary : Color.mOnSurface
  colorFgHover: usePrimaryColor ? Qt.darker(Color.mPrimary, 1.2) : Color.mOnHover
  colorBorder: Style.capsuleBorderColor
  colorBorderHover: Style.capsuleBorderColor

  onClicked: PanelService.getPanel("launcherPanel", screen)?.toggle()
  onMiddleClicked: PanelService.getPanel("launcherPanel", screen)?.toggle()
}
