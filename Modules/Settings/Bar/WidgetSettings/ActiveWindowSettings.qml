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
  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon
  property string valueScrollingMode: widgetData.scrollingMode || widgetMetadata.scrollingMode

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showIcon = valueShowIcon
    settings.scrollingMode = valueScrollingMode
    return settings
  }

  NToggle {
    id: showIcon
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.show-app-icon")
    checked: root.valueShowIcon
    onToggled: checked => root.valueShowIcon = checked
  }
    NComboBox {
    label: I18n.tr("bar.widget-settings.active-window.scrolling-mode")
    model: [{
        "key": "always",
        "name": I18n.tr("options.scrolling-modes.always")
      }, {
        "key": "hover",
        "name": I18n.tr("options.scrolling-modes.hover")
      }, {
        "key": "never",
        "name": I18n.tr("options.scrolling-modes.never")
      }]
    currentKey: valueScrollingMode
    onSelected: key => valueScrollingMode = key
    minimumWidth: 200 * scaling
  }
}
