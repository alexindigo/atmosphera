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
  property string valueClockStyle: widgetData.clockStyle !== undefined ? widgetData.clockStyle : "digital"

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.clockStyle = valueClockStyle;
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.style.label")
    description: I18n.tr("settings.desktop-widgets.clock.style.description")
    currentKey: valueClockStyle
    minimumWidth: 260 * Style.uiScaleRatio
    model: [
      {
        "key": "digital",
        "name": I18n.tr("settings.desktop-widgets.clock.style.digital")
      },
      {
        "key": "analog",
        "name": I18n.tr("settings.desktop-widgets.clock.style.analog")
      },
      {
        "key": "minimal",
        "name": I18n.tr("settings.desktop-widgets.clock.style.minimal")
      }
    ]
    onSelected: key => valueClockStyle = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.clock.show-background.label")
    description: I18n.tr("settings.desktop-widgets.clock.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }
}
