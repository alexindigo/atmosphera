import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NComboBox {
    label: I18n.tr("settings.launcher.settings.position.label")
    description: I18n.tr("settings.launcher.settings.position.description")
    Layout.fillWidth: true
    model: [
      {
        "key": "follow_bar",
        "name": I18n.tr("options.launcher.position.follow_bar")
      },
      {
        "key": "center",
        "name": I18n.tr("options.launcher.position.center")
      },
      {
        "key": "top_center",
        "name": I18n.tr("options.launcher.position.top_center")
      },
      {
        "key": "top_left",
        "name": I18n.tr("options.launcher.position.top_left")
      },
      {
        "key": "top_right",
        "name": I18n.tr("options.launcher.position.top_right")
      },
      {
        "key": "bottom_left",
        "name": I18n.tr("options.launcher.position.bottom_left")
      },
      {
        "key": "bottom_right",
        "name": I18n.tr("options.launcher.position.bottom_right")
      },
      {
        "key": "bottom_center",
        "name": I18n.tr("options.launcher.position.bottom_center")
      }
    ]
    currentKey: Settings.data.appLauncher.position
    onSelected: function (key) {
      Settings.data.appLauncher.position = key;
    }

    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.position")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.grid-view.label")
    description: I18n.tr("settings.launcher.settings.grid-view.description")
    checked: Settings.data.appLauncher.viewMode === "grid"
    onToggled: checked => Settings.data.appLauncher.viewMode = checked ? "grid" : "list"
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.viewMode")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.show-categories.label")
    description: I18n.tr("settings.launcher.settings.show-categories.description")
    checked: Settings.data.appLauncher.showCategories
    onToggled: checked => Settings.data.appLauncher.showCategories = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.showCategories")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.sort-by-usage.label")
    description: I18n.tr("settings.launcher.settings.sort-by-usage.description")
    checked: Settings.data.appLauncher.sortByMostUsed
    onToggled: checked => Settings.data.appLauncher.sortByMostUsed = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.sortByMostUsed")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.icon-mode.label")
    description: I18n.tr("settings.launcher.settings.icon-mode.description")
    checked: Settings.data.appLauncher.iconMode === "native"
    onToggled: checked => Settings.data.appLauncher.iconMode = checked ? "native" : "tabler"
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.iconMode")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.show-icon-background.label")
    description: I18n.tr("settings.launcher.settings.show-icon-background.description")
    checked: Settings.data.appLauncher.showIconBackground
    onToggled: checked => Settings.data.appLauncher.showIconBackground = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.showIconBackground")
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.ignore-mouse-input.label")
    description: I18n.tr("settings.launcher.settings.ignore-mouse-input.description")
    checked: Settings.data.appLauncher.ignoreMouseInput
    onToggled: checked => Settings.data.appLauncher.ignoreMouseInput = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("appLauncher.ignoreMouseInput")
  }
}
