import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property string valueTooltip: widgetData.tooltipText !== undefined ? widgetData.tooltipText : widgetMetadata.tooltipText

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.icon = valueIcon
    settings.exec = execInput.text
    settings.tooltipText = tooltipInput.text
    return settings
  }

  RowLayout {
    spacing: Style.marginM

    NLabel {
      label: I18n.tr("settings.control-center.shortcuts.custom-button.icon.label", "Icon")
      description: I18n.tr("settings.control-center.shortcuts.custom-button.icon.description", "The icon for the button.")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: valueIcon
      pointSize: Style.fontSizeXL
      visible: valueIcon !== ""
    }

    NButton {
      text: I18n.tr("settings.control-center.shortcuts.custom-button.browse", "Browse")
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: valueIcon
    onIconSelected: function (iconName) {
      valueIcon = iconName
    }
  }

  NTextInput {
    id: execInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.command.label", "Command")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.command.description", "The command to execute when the button is clicked.")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: widgetData?.exec || widgetMetadata.exec
  }

  NTextInput {
    id: tooltipInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.tooltip.label", "Tooltip")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.tooltip.description", "The tooltip to show when hovering over the button.")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: widgetData?.tooltipText || widgetMetadata.tooltipText
  }
}
