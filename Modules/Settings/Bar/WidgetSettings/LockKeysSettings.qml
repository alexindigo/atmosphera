import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowCapsLock: widgetData.showCapsLock !== undefined ? widgetData.showCapsLock : widgetMetadata.showCapsLock
  property bool valueShowNumLock: widgetData.showNumLock !== undefined ? widgetData.showNumLock : widgetMetadata.showNumLock
  property bool valueShowScrollLock: widgetData.showScrollLock !== undefined ? widgetData.showScrollLock : widgetMetadata.showScrollLock

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.showCapsLock = valueShowCapsLock
    settings.showNumLock = valueShowNumLock
    settings.showScrollLock = valueShowScrollLock
    return settings
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.lock-keys.show-caps-lock.label")
    description: I18n.tr("bar.widget-settings.lock-keys.show-caps-lock.description")
    checked: valueShowCapsLock
    onToggled: checked => valueShowCapsLock = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.lock-keys.show-num-lock.label")
    description: I18n.tr("bar.widget-settings.lock-keys.show-num-lock.description")
    checked: valueShowNumLock
    onToggled: checked => valueShowNumLock = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.lock-keys.show-scroll-lock.label")
    description: I18n.tr("bar.widget-settings.lock-keys.show-scroll-lock.description")
    checked: valueShowScrollLock
    onToggled: checked => valueShowScrollLock = checked
  }
}
