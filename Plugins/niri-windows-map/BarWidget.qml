import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
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

  readonly property string _size: pluginApi?.pluginSettings?.panelSize || "regular"
  readonly property string _corner: pluginApi?.pluginSettings?.corner || "bottomRight"

  readonly property var _sizeNames: ({
                                       "compact": "Compact",
                                       "regular": "Regular",
                                       "large": "Large"
                                     })
  readonly property var _cornerNames: ({
                                         "topLeft": "Top left",
                                         "topCenter": "Top center",
                                         "topRight": "Top right",
                                         "bottomLeft": "Bottom left",
                                         "bottomCenter": "Bottom center",
                                         "bottomRight": "Bottom right"
                                       })

  // Context menu models (flat menu — Size/Position swap the model in place,
  // "Back" returns). Current value is checkmarked.
  function _rootModel() {
    return [
          {
            "label": "Size: " + _sizeNames[_size],
            "action": "menu-size"
          },
          {
            "label": "Position: " + _cornerNames[_corner],
            "action": "menu-corner"
          },
          {
            "label": "Widget's Settings",
            "action": "widget-settings"
          }
        ];
  }

  function _sizeModel() {
    let items = [
          {
            "label": "← Size",
            "action": "back"
          }
        ];
    for (const key of ["compact", "regular", "large"])
      items.push({
                   "label": (_size === key ? "✓ " : "") + _sizeNames[key],
                   "action": "size:" + key
                 });
    return items;
  }

  function _cornerModel() {
    let items = [
          {
            "label": "← Position",
            "action": "back"
          }
        ];
    for (const key of ["topLeft", "topCenter", "topRight", "bottomLeft", "bottomCenter", "bottomRight"])
      items.push({
                   "label": (_corner === key ? "✓ " : "") + _cornerNames[key],
                   "action": "corner:" + key
                 });
    return items;
  }

  onClicked: {
    if (pluginApi) {
      // Don't pass this widget as the anchor button — the panel has explicit
      // bottom-right anchors; button-relative positioning would put it at the
      // bar instead.
      pluginApi.openPanel(root.screen);
    }
  }

  onRightClicked: {
    contextMenu.model = root._rootModel();
    PanelService.showContextMenu(contextMenu, root, screen);
  }

  NPopupContextMenu {
    id: contextMenu

    onTriggered: action => {
      if (action === "menu-size") {
        model = root._sizeModel();
        return;
      }
      if (action === "menu-corner") {
        model = root._cornerModel();
        return;
      }
      if (action === "back") {
        model = root._rootModel();
        return;
      }
      if (!pluginApi)
        return;
      if (action.startsWith("size:")) {
        pluginApi.pluginSettings.panelSize = action.substring(5);
        pluginApi.saveSettings();
        model = root._sizeModel();
        return;
      }
      if (action.startsWith("corner:")) {
        pluginApi.pluginSettings.corner = action.substring(7);
        pluginApi.saveSettings();
        model = root._cornerModel();
        return;
      }
      if (action === "widget-settings") {
        contextMenu.close();
        PanelService.closeContextMenu(screen);
        BarService.openPluginSettings(root.screen, pluginApi.manifest);
      }
    }
  }
}
