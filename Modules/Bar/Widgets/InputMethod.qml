import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.Keyboard
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

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

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"

  readonly property string displayMode: (widgetSettings.displayMode !== undefined) ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property bool showIcon: (widgetSettings.showIcon !== undefined) ? widgetSettings.showIcon : widgetMetadata.showIcon
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor

  property string currentLayout: KeyboardLayoutService.currentLayout

  readonly property bool imeActive: InputMethodService.fcitx5Available && InputMethodService.active
  readonly property string displayFlag: {
    if (imeActive) {
      var flag = InputMethodService.flagFor(InputMethodService.currentIMUniqueName, InputMethodService.currentIMLanguage);
      if (flag)
        return flag;
    }
    return xkbFlag(currentLayout);
  }
  readonly property string displayCode: {
    if (imeActive && InputMethodService.currentIMUniqueName) {
      var parts = InputMethodService.currentIMUniqueName.split("-");
      return parts[parts.length - 1].substring(0, 2).toUpperCase();
    }
    return currentLayout;
  }
  readonly property string displayName: {
    if (imeActive) {
      var found = InputMethodService.availableIMs.find(function (im) {
        return im.uniqueName === InputMethodService.currentIMUniqueName;
      });
      if (found && found.name)
        return found.name + " (" + (found.label || displayCode) + ")";
      return InputMethodService.currentIM || "IME";
    }
    return KeyboardLayoutService.fullLayoutName;
  }

  function xkbFlag(code) {
    var lc = (code || "").toLowerCase();
    return InputMethodService.flagFor("keyboard-" + lc, lc);
  }

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": Icon.settings
      }
    ]

    onTriggered: action => {
      contextMenu.close();
      PanelService.closeContextMenu(screen);

      if (action === "widget-settings") {
        BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
      }
    }
  }

  NPopupContextMenu {
    id: switcherMenu
    minWidth: 180

    property var switcherModel: []
    model: switcherModel

    onTriggered: (action, item) => {
      switcherMenu.close();
      PanelService.closeContextMenu(screen);

      if (action === "xkb-cycle") {
        CompositorService.cycleKeyboardLayout();
      } else if (action === "fctix5-select" && item) {
        InputMethodService.setCurrentIM(item.uniqueName || "");
      }
    }

    function buildModel() {
      var items = [];

      var code = root.currentLayout;
      var lc = code.toLowerCase();
      var flag = InputMethodService.flagFor("keyboard-" + lc, lc);
      items.push({
                   "label": (flag ? flag + "  " : "") + code.toUpperCase(),
                   "action": "xkb-cycle",
                   "enabled": true
                 });

      if (InputMethodService.availableIMs && InputMethodService.availableIMs.length > 0) {
        items.push({
                     "label": "──────────",
                     "action": "",
                     "enabled": false
                   });
        for (var j = 0; j < InputMethodService.availableIMs.length; j++) {
          var im = InputMethodService.availableIMs[j];
          var imFlag = InputMethodService.flagFor(im.uniqueName, im.language);
          var imLabel = imFlag ? (imFlag + "  " + (im.name || im.uniqueName)) : (im.name || im.uniqueName);
          items.push({
                       "label": imLabel,
                       "action": "fctix5-select",
                       "uniqueName": im.uniqueName,
                       "enabled": !root.imeActive || im.uniqueName !== InputMethodService.currentIMUniqueName
                     });
        }
      }

      switcherModel = items;
    }
  }

  BarPill {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    icon: root.showIcon ? "keyboard" : ""
    autoHide: false
    text: {
      if (isBarVertical) {
        if (root.displayMode === "flag")
          return root.displayFlag;
        if (root.displayMode === "text")
          return root.displayCode.substring(0, 3).toUpperCase();
        return root.displayFlag + root.displayCode.substring(0, 2);
      }
      if (root.displayMode === "flag")
        return root.displayFlag;
      if (root.displayMode === "text")
        return root.displayCode;
      return root.displayFlag + " " + root.displayCode;
    }
    tooltipText: root.displayName
    forceOpen: !root.showIcon || root.displayMode === "forceOpen"
    forceClose: root.showIcon && root.displayMode === "alwaysHide"
    onClicked: {
      switcherMenu.buildModel();
      PanelService.showContextMenu(switcherMenu, pill, screen);
    }
    onMiddleClicked: {
      if (root.imeActive) {
        InputMethodService.toggle();
      }
      CompositorService.cycleKeyboardLayout();
    }
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
  }
}
