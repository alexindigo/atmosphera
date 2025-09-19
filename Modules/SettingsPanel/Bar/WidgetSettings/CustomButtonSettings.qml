import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM * scaling

  property var widgetData: null
  property var widgetMetadata: null

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.icon = iconInput.text
    settings.leftClickExec = leftClickExecInput.text
    settings.rightClickExec = rightClickExecInput.text
    settings.middleClickExec = middleClickExecInput.text
    settings.textCommand = textCommandInput.text
    settings.textIntervalMs = parseInt(textIntervalInput.text || textIntervalInput.placeholderText, 10)
    return settings
  }

  NTextInput {
    id: iconInput
    Layout.fillWidth: true
    label: "Icon Name"
    description: "Select an icon from the library."
    placeholderText: "Enter icon name (e.g., cat, gear, house, ...)"
    text: widgetData?.icon || widgetMetadata.icon
  }

  RowLayout {
    spacing: Style.marginS * scaling
    Layout.alignment: Qt.AlignLeft
    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: iconInput.text
      visible: iconInput.text !== ""
    }
    NButton {
      text: "Browse"
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: iconInput.text
    onIconSelected: function (iconName) {
      iconInput.text = iconName
    }
  }

  NTextInput {
    id: leftClickExecInput
    Layout.fillWidth: true
    label: "Left Click Command"
    placeholderText: "Enter command to execute (app or custom script)"
    text: widgetData?.leftClickExec || widgetMetadata.leftClickExec
  }

  NTextInput {
    id: rightClickExecInput
    Layout.fillWidth: true
    label: "Right Click Command"
    placeholderText: "Enter command to execute (app or custom script)"
    text: widgetData?.rightClickExec || widgetMetadata.rightClickExec
  }

  NTextInput {
    id: middleClickExecInput
    Layout.fillWidth: true
    label: "Middle Click Command"
    placeholderText: "Enter command to execute (app or custom script)"
    text: widgetData.middleClickExec || widgetMetadata.middleClickExec
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    text: "Dynamic Text"
    font.pointSize: Style.fontSizeM * scaling
    font.weight: Style.fontWeightBold
    color: Color.mPrimary
  }

  NTextInput {
    id: textCommandInput
    Layout.fillWidth: true
    label: "Text Command"
    description: "Shell command to run periodically (first line becomes the text)."
    placeholderText: "echo \"Hello World\""
    text: widgetData?.textCommand || widgetMetadata.textCommand
  }

  NTextInput {
    id: textIntervalInput
    Layout.fillWidth: true
    label: "Refresh Interval"
    description: "Interval in milliseconds."
    placeholderText: String(widgetMetadata.textIntervalMs || 3000)
    text: widgetData && widgetData.textIntervalMs !== undefined ? String(widgetData.textIntervalMs) : ""
  }
}
