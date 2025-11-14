import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  property string valueLabelMode: widgetData.labelMode !== undefined ? widgetData.labelMode : (widgetMetadata ? widgetMetadata.labelMode : "index")
  property bool valueHideUnoccupied: widgetData.hideUnoccupied !== undefined ? widgetData.hideUnoccupied : (widgetMetadata ? widgetMetadata.hideUnoccupied : false)
  property bool valueShowWorkspaceNumbers: widgetData.showWorkspaceNumbers !== undefined ? widgetData.showWorkspaceNumbers : (widgetMetadata ? widgetMetadata.showWorkspaceNumbers : true)
  property bool valueShowNumbersOnlyWhenOccupied: widgetData.showNumbersOnlyWhenOccupied !== undefined ? widgetData.showNumbersOnlyWhenOccupied : (widgetMetadata ? widgetMetadata.showNumbersOnlyWhenOccupied : true)
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : (widgetMetadata ? widgetMetadata.colorizeIcons : false)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.labelMode = valueLabelMode
    settings.hideUnoccupied = valueHideUnoccupied
    settings.showWorkspaceNumbers = valueShowWorkspaceNumbers
    settings.showNumbersOnlyWhenOccupied = valueShowNumbersOnlyWhenOccupied
    settings.colorizeIcons = valueColorizeIcons
    return settings
  }

  NComboBox {
    id: labelModeCombo
    label: I18n.tr("bar.widget-settings.workspace.label-mode.label")
    description: I18n.tr("bar.widget-settings.workspace.label-mode.description")
    model: [{
        "key": "none",
        "name": I18n.tr("options.workspace-labels.none")
      }, {
        "key": "index",
        "name": I18n.tr("options.workspace-labels.index")
      }, {
        "key": "name",
        "name": I18n.tr("options.workspace-labels.name")
      }]
    currentKey: widgetData.labelMode || widgetMetadata.labelMode
    onSelected: key => valueLabelMode = key
    minimumWidth: 200
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.hide-unoccupied.label")
    description: I18n.tr("bar.widget-settings.workspace.hide-unoccupied.description")
    checked: valueHideUnoccupied
    onToggled: checked => valueHideUnoccupied = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.colorize-icons.label")
    description: I18n.tr("bar.widget-settings.active-window.colorize-icons.description")
    checked: root.valueColorizeIcons
    onToggled: checked => root.valueColorizeIcons = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar-grouped.show-workspace-numbers.label")
    description: I18n.tr("bar.widget-settings.taskbar-grouped.show-workspace-numbers.description")
    checked: root.valueShowWorkspaceNumbers
    onToggled: checked => root.valueShowWorkspaceNumbers = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar-grouped.show-numbers-only-when-occupied.label")
    description: I18n.tr("bar.widget-settings.taskbar-grouped.show-numbers-only-when-occupied.description")
    checked: root.valueShowNumbersOnlyWhenOccupied
    onToggled: checked => root.valueShowNumbersOnlyWhenOccupied = checked
    visible: root.valueShowWorkspaceNumbers
  }
}
