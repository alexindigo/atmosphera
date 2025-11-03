import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var widgetData: null
  property var widgetMetadata: null

  QtObject {
    id: _settings

    property string icon: (widgetData && widgetData.icon !== undefined) ? widgetData.icon : widgetMetadata.icon
    property string onStateIcon: (widgetData && widgetData.onStateIcon !== undefined) ? widgetData.onStateIcon : widgetMetadata.onStateIcon
    property string onClicked: (widgetData && widgetData.onClicked !== undefined) ? widgetData.onClicked : widgetMetadata.onClicked
    property string onRightClicked: (widgetData && widgetData.onRightClicked !== undefined) ? widgetData.onRightClicked : widgetMetadata.onRightClicked
    property string onMiddleClicked: (widgetData && widgetData.onMiddleClicked !== undefined) ? widgetData.onMiddleClicked : widgetMetadata.onMiddleClicked
    property string onStateCommand: (widgetData && widgetData.onStateCommand !== undefined) ? widgetData.onStateCommand : widgetMetadata.onStateCommand
    property string generalTooltipText: (widgetData && widgetData.generalTooltipText !== undefined) ? widgetData.generalTooltipText : widgetMetadata.generalTooltipText
    property bool enableOnStateLogic: (widgetData && widgetData.enableOnStateLogic !== undefined) ? widgetData.enableOnStateLogic : widgetMetadata.enableOnStateLogic


  }

  function saveSettings() {
    var saved = {
      id: widgetData.id,
      icon: _settings.icon,
      onStateIcon: _settings.onStateIcon,
      onClicked: _settings.onClicked,
      onRightClicked: _settings.onRightClicked,
      onMiddleClicked: _settings.onMiddleClicked,
      onStateCommand: _settings.onStateCommand,
      generalTooltipText: _settings.generalTooltipText,
      enableOnStateLogic: _settings.enableOnStateLogic
    }

    return saved
  }

  RowLayout {
    spacing: Style.marginM

    NLabel {
      label: I18n.tr("settings.control-center.shortcuts.custom-button.icon.label")
      description: I18n.tr("settings.control-center.shortcuts.custom-button.icon.description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: _settings.icon || widgetMetadata.icon
      pointSize: Style.fontSizeXL
      visible: (_settings.icon || widgetMetadata.icon) !== ""
    }

    NButton {
      text: I18n.tr("settings.control-center.shortcuts.custom-button.browse")
      onClicked: iconPicker.open()
    }
  }

  NIconPicker {
    id: iconPicker
    initialIcon: _settings.icon
    onIconSelected: function (iconName) {
      _settings.icon = iconName
    }
  }

  NTextInput {
    id: generalTooltipTextInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.general-tooltip-text.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.general-tooltip-text.description")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: _settings.generalTooltipText
    onTextChanged: _settings.generalTooltipText = text
  }

  NTextInput {
    id: onClickedCommandInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onClicked
    onTextChanged: _settings.onClicked = text
  }

  NTextInput {
    id: onRightClickedCommandInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-right-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-right-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onRightClicked
    onTextChanged: _settings.onRightClicked = text
  }

  NTextInput {
    id: onMiddleClickedCommandInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-middle-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-middle-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onMiddleClicked
    onTextChanged: _settings.onMiddleClicked = text
  }

  NDivider {}

  NToggle {
    id: enableOnStateLogicToggle
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.enable-on-state-logic.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.enable-on-state-logic.description")
    checked: _settings.enableOnStateLogic
    onToggled: checked => _settings.enableOnStateLogic = checked
  }

  // On-State Icon
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    visible: _settings.enableOnStateLogic

    NLabel {
      label: I18n.tr("settings.control-center.shortcuts.custom-button.on-state-icon.label")
      description: I18n.tr("settings.control-center.shortcuts.custom-button.on-state-icon.description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: _settings.onStateIcon || widgetMetadata.onStateIcon
      pointSize: Style.fontSizeXL
      visible: (_settings.onStateIcon || widgetMetadata.onStateIcon) !== ""
    }

    NButton {
      Layout.fillWidth: true
      text: I18n.tr("settings.control-center.shortcuts.custom-button.browse")
      onClicked: onStateIconPicker.open()
    }
  }

  NIconPicker {
    id: onStateIconPicker
    initialIcon: _settings.onStateIcon
    onIconSelected: function (iconName) {
      _settings.onStateIcon = iconName
    }
  }

  NTextInput {
    id: onStateCommandInput
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-state-command.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-state-command.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onStateCommand
    onTextChanged: _settings.onStateCommand = text
    enabled: _settings.enableOnStateLogic
    visible: _settings.enableOnStateLogic
  }
}
