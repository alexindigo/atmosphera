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

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.icon = iconInput.text
    settings.leftClickExec = leftClickExecInput.text
    settings.rightClickExec = rightClickExecInput.text
    settings.middleClickExec = middleClickExecInput.text
    return settings
  }

  // Icon setting
  NTextInput {
    id: iconInput
    Layout.fillWidth: true
    label: "Icon Name"
    description: "Choose a name from the Material Icon set."
    placeholderText: "Enter icon name (e.g., favorite, home, settings)"
    text: widgetData?.icon || widgetMetadata.icon
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
}
