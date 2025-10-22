import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property bool valueTextStream: widgetData.textStream !== undefined ? widgetData.textStream : widgetMetadata.textStream

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.icon = valueIcon
    settings.leftClickExec = leftClickExecInput.text
    settings.rightClickExec = rightClickExecInput.text
    settings.middleClickExec = middleClickExecInput.text
    settings.textCommand = textCommandInput.text
    settings.textStream = valueTextStream
    settings.textIntervalMs = parseInt(textIntervalInput.text || textIntervalInput.placeholderText, 10)
    return settings
  }

  RowLayout {
    spacing: Style.marginM

    NLabel {
      label: I18n.tr("bar.widget-settings.custom-button.icon.label")
      description: I18n.tr("bar.widget-settings.custom-button.icon.description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: valueIcon
      pointSize: Style.fontSizeXL
      visible: valueIcon !== ""
    }

    NButton {
      text: I18n.tr("bar.widget-settings.custom-button.browse")
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
    id: leftClickExecInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.custom-button.left-click.label")
    description: I18n.tr("bar.widget-settings.custom-button.left-click.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: widgetData?.leftClickExec || widgetMetadata.leftClickExec
  }

  NTextInput {
    id: rightClickExecInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.custom-button.right-click.label")
    description: I18n.tr("bar.widget-settings.custom-button.right-click.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: widgetData?.rightClickExec || widgetMetadata.rightClickExec
  }

  NTextInput {
    id: middleClickExecInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.custom-button.middle-click.label")
    description: I18n.tr("bar.widget-settings.custom-button.middle-click.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: widgetData.middleClickExec || widgetMetadata.middleClickExec
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: I18n.tr("bar.widget-settings.custom-button.dynamic-text")
  }

  NToggle {
    id: textStreamInput
    label: I18n.tr("bar.widget-settings.custom-button.text-stream.label")
    description: I18n.tr("bar.widget-settings.custom-button.text-stream.description")
    checked: valueTextStream
    onToggled: checked => valueTextStream = checked
  }

  NTextInput {
    id: textCommandInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.custom-button.display-command-output.label")
    description: valueTextStream ? I18n.tr("bar.widget-settings.custom-button.display-command-output.stream-description") : I18n.tr("bar.widget-settings.custom-button.display-command-output.description")
    placeholderText: I18n.tr("placeholders.command-example")
    text: widgetData?.textCommand || widgetMetadata.textCommand
  }

  NTextInput {
    id: textIntervalInput
    Layout.fillWidth: true
    visible: !valueTextStream
    label: I18n.tr("bar.widget-settings.custom-button.refresh-interval.label")
    description: I18n.tr("bar.widget-settings.custom-button.refresh-interval.description")
    placeholderText: String(widgetMetadata.textIntervalMs || 3000)
    text: widgetData && widgetData.textIntervalMs !== undefined ? String(widgetData.textIntervalMs) : ""
  }
}
