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
  property bool valueShowUnreadBadge: widgetData.showUnreadBadge !== undefined ? widgetData.showUnreadBadge : widgetMetadata.showUnreadBadge
  property bool valueHideWhenZero: widgetData.hideWhenZero !== undefined ? widgetData.hideWhenZero : widgetMetadata.hideWhenZero

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showUnreadBadge = valueShowUnreadBadge
    settings.hideWhenZero = valueHideWhenZero
    return settings
  }

  NCheckbox {
    label: "Show unread badge"
    checked: valueShowUnreadBadge
    onToggled: checked => valueShowUnreadBadge = checked
  }

  NCheckbox {
    label: "Hide badge when zero"
    checked: valueHideWhenZero
    onToggled: checked => valueHideWhenZero = checked
  }
}
