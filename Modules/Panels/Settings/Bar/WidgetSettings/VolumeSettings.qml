import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property string valueMiddleClickCommand: widgetData.middleClickCommand !== undefined ? widgetData.middleClickCommand : widgetMetadata.middleClickCommand
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  function saveSettings(fields) {
    if (fields)
      settingsChanged(fields);
  }

  NComboBox {
    label: I18n.tr("common.display-mode")
    description: I18n.tr("bar.volume.display-mode-description")
    minimumWidth: 200
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("display-modes.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("display-modes.always-show")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("display-modes.always-hide")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => {
      valueDisplayMode = key;
      saveSettings({displayMode: valueDisplayMode});
    }
    defaultValue: widgetMetadata.displayMode
  }

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
      valueIconColor = key;
      saveSettings({iconColor: valueIconColor});
    }
    defaultValue: widgetMetadata.iconColor
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
      valueTextColor = key;
      saveSettings({textColor: valueTextColor});
    }
    defaultValue: widgetMetadata.textColor
  }

  // Middle click command
  NTextInput {
    label: I18n.tr("bar.custom-button.middle-click-label")
    description: I18n.tr("panels.audio.on-middle-clicked-description")
    placeholderText: I18n.tr("panels.audio.external-mixer-placeholder")
    text: valueMiddleClickCommand
    onTextEdited: {
      valueMiddleClickCommand = text;
      saveSettings({middleClickCommand: valueMiddleClickCommand});
    }
    defaultValue: widgetMetadata.middleClickCommand
  }
}
