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

  // Flat context menu: all size + position options in one list with
  // disabled section headers. Options reserve an icon slot on the left;
  // only the current value shows a check icon there
  function _option(key, name, current) {
    let opt = {
      "label": name,
      "key": key,
      "reserveIconSpace": true
    };
    if (current)
      opt.icon = Icon.check;
    return opt;
  }

  function _rootModel() {
    let items = [
          {
            "label": "Size",
            "key": "hdr-size",
            "enabled": false
          }
        ];
    for (const key of ["compact", "regular", "large"])
      items.push(root._option("size:" + key, _sizeNames[key], _size === key));
    items.push({
                 "label": "Position",
                 "key": "hdr-corner",
                 "enabled": false
               });
    for (const key of ["topLeft", "topCenter", "topRight", "bottomLeft", "bottomCenter", "bottomRight"])
      items.push(root._option("corner:" + key, _cornerNames[key], _corner === key));
    items.push({
                 "label": "",
                 "key": "sep-settings",
                 "isSeparator": true,
                 "enabled": false
               });
    items.push({
                 "label": "Widget's Settings",
                 "key": "widget-settings"
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
      if (!pluginApi)
        return;
      if (action.startsWith("size:"))
        pluginApi.pluginSettings.panelSize = action.substring(5);
      else if (action.startsWith("corner:"))
        pluginApi.pluginSettings.corner = action.substring(7);
      else if (action === "widget-settings") {
        contextMenu.close();
        PanelService.closeContextMenu(screen);
        BarService.openPluginSettings(root.screen, pluginApi.manifest);
        return;
      } else
        return;  // headers/separator rows are disabled and never reach here

      pluginApi.saveSettings();
      // Any selection closes the menu
      contextMenu.close();
      PanelService.closeContextMenu(screen);
    }
  }
}
