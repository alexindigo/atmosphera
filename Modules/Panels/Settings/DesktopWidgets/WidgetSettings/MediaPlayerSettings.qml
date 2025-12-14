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
  property string valueVisualizerType: widgetData.visualizerType !== undefined ? widgetData.visualizerType : (widgetMetadata ? widgetMetadata.visualizerType : "")

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.visualizerType = valueVisualizerType;
    return settings;
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.show-background.label")
    description: I18n.tr("settings.desktop-widgets.media-player.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.media-player.visualizer-type.label")
    description: I18n.tr("settings.desktop-widgets.media-player.visualizer-type.description")
    model: [
      {
        "key": "",
        "name": I18n.tr("options.visualizer-types.none")
      },
      {
        "key": "linear",
        "name": I18n.tr("options.visualizer-types.linear")
      },
      {
        "key": "mirrored",
        "name": I18n.tr("options.visualizer-types.mirrored")
      },
      {
        "key": "wave",
        "name": I18n.tr("options.visualizer-types.wave")
      }
    ]
    currentKey: valueVisualizerType
    onSelected: key => valueVisualizerType = key
  }
}
