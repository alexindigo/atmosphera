import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

AtmoIconButton {
  id: root

  // Injected by the plugin system
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  icon: "map"
  tooltipText: "Niri Windows Map"
  baseSize: Style.getCapsuleHeightForScreen(screen ? screen.name : "")
  applyUiScale: false
  colorBg: Style.capsuleColor
  colorFg: Color.mOnSurface
  colorBgHover: Color.mHover
  colorFgHover: Color.mOnHover
  colorBorder: Style.capsuleBorderColor
  colorBorderHover: Style.capsuleBorderColor

  onClicked: {
    if (pluginApi) {
      // Don't pass this widget as the anchor button — the panel has explicit
      // bottom-right anchors; button-relative positioning would put it at the
      // bar instead.
      pluginApi.openPanel(root.screen);
    }
  }
}
