import QtQuick
import QtQuick.Layouts
import QtQml.Models // Import ListModel
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var widgetData: null
  property var widgetMetadata: null

  QtObject {
    id: _settings

    property string icon: (widgetData && widgetData.icon !== undefined) ? widgetData.icon : widgetMetadata.icon
    property string onClicked: (widgetData && widgetData.onClicked !== undefined) ? widgetData.onClicked : widgetMetadata.onClicked
    property string onRightClicked: (widgetData && widgetData.onRightClicked !== undefined) ? widgetData.onRightClicked : widgetMetadata.onRightClicked
    property string onMiddleClicked: (widgetData && widgetData.onMiddleClicked !== undefined) ? widgetData.onMiddleClicked : widgetMetadata.onMiddleClicked
    property ListModel _stateChecksListModel: ListModel {}
    property string stateChecksJson: "[]"
    property string generalTooltipText: (widgetData && widgetData.generalTooltipText !== undefined) ? widgetData.generalTooltipText : widgetMetadata.generalTooltipText
    property bool enableOnStateLogic: (widgetData && widgetData.enableOnStateLogic !== undefined) ? widgetData.enableOnStateLogic : widgetMetadata.enableOnStateLogic

    Component.onCompleted: {
      stateChecksJson = (widgetData && widgetData.stateChecksJson !== undefined) ? widgetData.stateChecksJson : widgetMetadata.stateChecksJson || "[]"
      try {
        var initialChecks = JSON.parse(stateChecksJson)
        if (initialChecks && Array.isArray(initialChecks)) {
          for (var i = 0; i < initialChecks.length; i++) {
            var item = initialChecks[i]
            if (item && typeof item === "object") {
              _settings._stateChecksListModel.append({
                command: item.command || "",
                icon: item.icon || ""
              })
            } else {
              console.warn("⚠️ Invalid stateChecks entry at index " + i + ":", item)
            }
          }
        }
      } catch (e) {
        console.error("CustomButtonSettings: Failed to parse stateChecksJson:", e.message)
      }
    }
  }

  function saveSettings() {
    var savedStateChecksArray = []
    for (var i = 0; i < _settings._stateChecksListModel.count; i++) {
      savedStateChecksArray.push(_settings._stateChecksListModel.get(i))
    }
    _settings.stateChecksJson = JSON.stringify(savedStateChecksArray)

    return {
      id: widgetData.id,
      icon: _settings.icon,
      onClicked: _settings.onClicked,
      onRightClicked: _settings.onRightClicked,
      onMiddleClicked: _settings.onMiddleClicked,
      stateChecksJson: _settings.stateChecksJson,
      generalTooltipText: _settings.generalTooltipText,
      enableOnStateLogic: _settings.enableOnStateLogic
    }
  }

  RowLayout {
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("settings.control-center.shortcuts.custom-button.icon.label")
      description: I18n.tr("settings.control-center.shortcuts.custom-button.icon.description")
    }

    NIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: _settings.icon || widgetMetadata.icon
      pointSize: Style?.fontSizeXL ?? 24
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
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.general-tooltip-text.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.general-tooltip-text.description")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: _settings.generalTooltipText
    onTextChanged: _settings.generalTooltipText = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onClicked
    onTextChanged: _settings.onClicked = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("settings.control-center.shortcuts.custom-button.on-right-clicked.label")
    description: I18n.tr("settings.control-center.shortcuts.custom-button.on-right-clicked.description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onRightClicked
    onTextChanged: _settings.onRightClicked = text
  }

  NTextInput {
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

  ColumnLayout {
    Layout.fillWidth: true
    visible: _settings.enableOnStateLogic
    spacing: (Style?.marginM ?? 8) * 2

    NLabel {
      label: "State Checks"
    }

    Repeater {
      model: _settings._stateChecksListModel
      delegate: ColumnLayout {
        Layout.fillWidth: true
        spacing: Style?.marginM ?? 8
        property int currentIndex: index

        RowLayout {
          Layout.fillWidth: true
          spacing: Style?.marginS ?? 4

          NTextInput {
            Layout.fillWidth: true
            label: "Command"
            text: model.command
            onEditingFinished: _settings._stateChecksListModel.set(currentIndex, { "command": text, "icon": model.icon })
          }

          NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: model.icon
            visible: model.icon !== undefined && model.icon !== ""
          }

          NButton {
            text: "Browse Icon"
            Layout.preferredWidth: Style?.buttonWidthM ?? 100
            onClicked: iconPickerDelegate.open()
          }

          NIconPicker {
            id: iconPickerDelegate
            initialIcon: model.icon
            onIconSelected: function (iconName) {
              _settings._stateChecksListModel.set(currentIndex, { "command": model.command, "icon": iconName })
            }
          }

          NButton {
            text: "Remove"
            Layout.preferredWidth: Style?.buttonWidthM ?? 100
            onClicked: _settings._stateChecksListModel.remove(currentIndex)
          }
        }

        NDivider {}
      }
    }

    NButton {
      text: "Add State Check"
      onClicked: _settings._stateChecksListModel.append({ command: "", icon: "" })
    }
  }

  NDivider {}
}