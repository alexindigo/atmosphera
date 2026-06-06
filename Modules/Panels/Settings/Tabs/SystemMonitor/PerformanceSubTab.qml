import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.system.atmosphera-performance-disable-wallpaper-label")
    description: I18n.tr("panels.system.atmosphera-performance-disable-wallpaper-description")
    checked: !Settings.data.atmospheraPerformance.disableWallpaper
    defaultValue: !Settings.getDefaultValue("atmospheraPerformance.disableWallpaper")
    onToggled: checked => Settings.data.atmospheraPerformance.disableWallpaper = !checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.system.atmosphera-performance-disable-desktop-widgets-label")
    description: I18n.tr("panels.system.atmosphera-performance-disable-desktop-widgets-description")
    checked: !Settings.data.atmospheraPerformance.disableDesktopWidgets
    defaultValue: !Settings.getDefaultValue("atmospheraPerformance.disableDesktopWidgets")
    onToggled: checked => Settings.data.atmospheraPerformance.disableDesktopWidgets = !checked
  }
}
