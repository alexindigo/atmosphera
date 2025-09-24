import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM * scaling

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowAlbumArt: widgetData.showAlbumArt !== undefined ? widgetData.showAlbumArt : widgetMetadata.showAlbumArt
  property bool valueShowVisualizer: widgetData.showVisualizer !== undefined ? widgetData.showVisualizer : widgetMetadata.showVisualizer
  property string valueVisualizerType: widgetData.visualizerType || widgetMetadata.visualizerType

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showAlbumArt = valueShowAlbumArt
    settings.showVisualizer = valueShowVisualizer
    settings.visualizerType = valueVisualizerType
    return settings
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.show-album-art")
    checked: valueShowAlbumArt
    onToggled: checked => valueShowAlbumArt = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.media-mini.show-visualizer")
    checked: valueShowVisualizer
    onToggled: checked => valueShowVisualizer = checked
  }

  NComboBox {
    visible: valueShowVisualizer
    label: I18n.tr("bar.widget-settings.media-mini.visualizer-type")
    model: ListModel {
      ListElement {
        key: "linear"
        name: "Linear"
      }
      ListElement {
        key: "mirrored"
        name: "Mirrored"
      }
      ListElement {
        key: "wave"
        name: "Wave"
      }
    }
    currentKey: valueVisualizerType
    onSelected: key => valueVisualizerType = key
    minimumWidth: 200 * scaling
  }
}
