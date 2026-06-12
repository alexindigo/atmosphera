import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Power
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

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId] ?? {}
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor

  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: PowerProfileService.atmospheraPerformanceMode ? Color.mPrimary : Style.capsuleColor
  colorFg: PowerProfileService.atmospheraPerformanceMode ? Color.mOnPrimary : Color.resolveColorKey(iconColorKey)
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  icon: PowerProfileService.atmospheraPerformanceMode ? "rocket" : "rocket-off"
  tooltipText: PowerProfileService.atmospheraPerformanceMode ? I18n.tr("tooltips.atmosphera-performance-enabled") : I18n.tr("tooltips.atmosphera-performance-enabled")
  tooltipDirection: BarService.getTooltipDirection(screen?.name)
  onClicked: PowerProfileService.toggleAtmospheraPerformance()

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
      contextMenu.close();
      PanelService.closeContextMenu(screen);

      if (action === "widget-settings") {
        BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
      }
    }
  }

  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }
}
