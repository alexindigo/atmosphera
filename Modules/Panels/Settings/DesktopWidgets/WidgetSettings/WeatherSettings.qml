import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : (widgetMetadata ? widgetMetadata.showBackground : true)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    return settings;
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.weather.show-background.label")
    description: I18n.tr("settings.desktop-widgets.weather.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }
}
