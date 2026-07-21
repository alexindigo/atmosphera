import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.showIcon = valueShowIcon;
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settingsChanged(settings);
  }

  NComboBox {
    label: I18n.tr("common.display-mode")
    description: I18n.tr("bar.input-method.display-mode-description")
    minimumWidth: 200
    model: [
      {
        "key": "flag",
        "name": I18n.tr("input-method.display-modes.flag")
      },
      {
        "key": "text",
        "name": I18n.tr("input-method.display-modes.text")
      },
      {
        "key": "flag+text",
        "name": I18n.tr("input-method.display-modes.flag-and-text")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => {
      valueDisplayMode = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.displayMode
  }

  NToggle {
    label: I18n.tr("bar.custom-button.show-icon-label")
    description: I18n.tr("bar.input-method.show-icon-description")
    checked: valueShowIcon
    onToggled: checked => {
      valueShowIcon = checked;
      saveSettings();
    }
    defaultValue: widgetMetadata.showIcon
  }

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
      valueIconColor = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.iconColor
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
      valueTextColor = key;
      saveSettings();
    }
    defaultValue: widgetMetadata.textColor
  }
}
