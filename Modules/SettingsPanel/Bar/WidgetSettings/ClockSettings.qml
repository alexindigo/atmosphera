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
  property string valueDisplayFormat: widgetData.displayFormat !== undefined ? widgetData.displayFormat : widgetMetadata.displayFormat

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.displayFormat = valueDisplayFormat
    return settings
  }

  NComboBox {
    label: "Display format"
    model: ListModel {
      ListElement {
        key: "time"
        name: "HH:mm"
      }
      ListElement {
        key: "time-seconds"
        name: "HH:mm:ss"
      }
      ListElement {
        key: "time-date"
        name: "HH:mm + Date"
      }
      ListElement {
        key: "time-date-short"
        name: "HH:mm + Short date"
      }
    }
    currentKey: valueDisplayFormat
    onSelected: key => valueDisplayFormat = key
    minimumWidth: 230 * scaling
  }
}
