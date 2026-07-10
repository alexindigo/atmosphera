import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  enabled: Settings.data.desktopWidgets.enabled
  spacing: Style.marginL

  readonly property var availableItems: [
    {
      "id": "add-app-shortcut",
      "labelKey": "panels.desktop-widgets.menu-add-app-shortcut",
      "icon": Icon.add
    },
    {
      "id": "change-wallpaper",
      "labelKey": "panels.desktop-widgets.menu-change-wallpaper",
      "icon": Icon.settingsWallpaper
    },
    {
      "id": "display-settings",
      "labelKey": "panels.desktop-widgets.menu-display-settings",
      "icon": Icon.settingsDisplay
    },
    {
      "id": "toggle-edit-mode",
      "labelKey": "panels.desktop-widgets.menu-toggle-edit-mode",
      "icon": Icon.edit
    }
  ]

  NToggle {
    id: menuEnabledToggle
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.menu-section-title")
    description: I18n.tr("panels.desktop-widgets.menu-section-description")
    checked: Settings.data.desktopContextMenu.enabled
    defaultValue: true
    onToggled: checked => Settings.data.desktopContextMenu.enabled = checked
  }

  ColumnLayout {
    enabled: Settings.data.desktopContextMenu.enabled
    spacing: Style.marginS

    Repeater {
      id: menuItemsRepeater
      model: Settings.data.desktopContextMenu.items

      RowLayout {
        spacing: Style.marginS
        Layout.fillWidth: true

        NToggle {
          Layout.fillWidth: true
          label: {
            var itemId = modelData.id;
            for (var i = 0; i < root.availableItems.length; i++) {
              if (root.availableItems[i].id === itemId)
                return I18n.tr(root.availableItems[i].labelKey);
            }
            return itemId;
          }
          checked: true
          onToggled: c => {
            if (!c)
              _removeItem(index);
          }
        }

        NIconButton {
          baseSize: 24
          icon: Icon.chevronUp
          tooltipText: I18n.tr("panels.desktop-widgets.menu-move-up")
          enabled: index > 0
          onClicked: _swapItems(index, index - 1)
        }

        NIconButton {
          baseSize: 24
          icon: Icon.chevronDown
          tooltipText: I18n.tr("panels.desktop-widgets.menu-move-down")
          enabled: index < Settings.data.desktopContextMenu.items.length - 1
          onClicked: _swapItems(index, index + 1)
        }
      }
    }

    NDivider {
      Layout.topMargin: Style.marginM
      Layout.bottomMargin: Style.marginS
    }

    NHeader {
      label: I18n.tr("panels.desktop-widgets.menu-add-item")
      visible: _unaddedItems().length > 0
    }

    Repeater {
      model: _unaddedItems()

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: modelData.icon
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }

        NText {
          text: I18n.tr(modelData.labelKey)
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.add")
          icon: Icon.add
          fontSize: Style.fontSizeS
          onClicked: _addItem(modelData.id)
        }
      }
    }
  }

  function _itemInList(id) {
    var items = Settings.data.desktopContextMenu.items || [];
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === id)
        return true;
    }
    return false;
  }

  function _unaddedItems() {
    var result = [];
    for (var i = 0; i < root.availableItems.length; i++) {
      if (!_itemInList(root.availableItems[i].id))
        result.push(root.availableItems[i]);
    }
    return result;
  }

  function _addItem(id) {
    var items = (Settings.data.desktopContextMenu.items || []).slice();
    items.push({
                 "id": id
               });
    Settings.data.desktopContextMenu.items = items;
  }

  function _removeItem(index) {
    var items = (Settings.data.desktopContextMenu.items || []).slice();
    if (index >= 0 && index < items.length) {
      items.splice(index, 1);
      Settings.data.desktopContextMenu.items = items;
    }
  }

  function _swapItems(a, b) {
    var items = (Settings.data.desktopContextMenu.items || []).slice();
    if (a >= 0 && a < items.length && b >= 0 && b < items.length) {
      var temp = items[a];
      items[a] = items[b];
      items[b] = temp;
      Settings.data.desktopContextMenu.items = items;
    }
  }
}
