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
  property bool valueOnlyActiveWorkspaces: widgetData.onlyActiveWorkspaces !== undefined ? widgetData.onlyActiveWorkspaces : widgetMetadata.onlyActiveWorkspaces
  property bool valueOnlySameOutput: widgetData.onlySameOutput !== undefined ? widgetData.onlySameOutput : widgetMetadata.onlySameOutput
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.onlySameOutput = valueOnlySameOutput
    settings.onlyActiveWorkspaces = valueOnlyActiveWorkspaces
    settings.colorizeIcons = valueColorizeIcons
    return settings
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.only-same-output.label")
    description: I18n.tr("bar.widget-settings.taskbar.only-same-output.description")
    checked: root.valueOnlySameOutput
    onToggled: checked => root.valueOnlySameOutput = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.only-active-workspaces.label")
    description: I18n.tr("bar.widget-settings.taskbar.only-active-workspaces.description")
    checked: root.valueOnlyActiveWorkspaces
    onToggled: checked => root.valueOnlyActiveWorkspaces = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.colorize-icons.label")
    description: I18n.tr("bar.widget-settings.taskbar.colorize-icons.description")
    checked: root.valueColorizeIcons
    onToggled: checked => root.valueColorizeIcons = checked
  }
}
