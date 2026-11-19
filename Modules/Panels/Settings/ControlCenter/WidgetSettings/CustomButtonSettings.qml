import QtQml.Models
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  Layout.preferredWidth: Math.round(600 * Style.uiScaleRatio)
  implicitWidth: Layout.preferredWidth

  property var widgetData: null
  property var widgetMetadata: null
  property var rootSettings: null

  signal settingsChanged(var settings)

  QtObject {
    id: _settings

    property string icon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
    property string onClicked: widgetData.onClicked !== undefined ? widgetData.onClicked : widgetMetadata.onClicked
    property string onRightClicked: widgetData.onRightClicked !== undefined ? widgetData.onRightClicked : widgetMetadata.onRightClicked
    property string onMiddleClicked: widgetData.onMiddleClicked !== undefined ? widgetData.onMiddleClicked : widgetMetadata.onMiddleClicked
    property ListModel _stateChecksListModel: ListModel {}
    property string stateChecksJson: "[]"
    property string generalTooltipText: widgetData.generalTooltipText !== undefined ? widgetData.generalTooltipText : widgetMetadata.generalTooltipText
    property bool enableOnStateLogic: widgetData.enableOnStateLogic !== undefined ? widgetData.enableOnStateLogic : widgetMetadata.enableOnStateLogic
    property bool showExecTooltip: widgetData.showExecTooltip !== undefined ? widgetData.showExecTooltip : widgetMetadata.showExecTooltip

    function populateStateChecks() {
      try {
        var initialChecks = JSON.parse(stateChecksJson);
        if (initialChecks && Array.isArray(initialChecks)) {
          for (var i = 0; i < initialChecks.length; i++) {
            var item = initialChecks[i];
            if (item && typeof item === "object") {
              _settings._stateChecksListModel.append({
                                                       "command": item.command || "",
                                                       "icon": item.icon || ""
                                                     });
            } else {
              Logger.w("CustomButtonSettings", "Invalid stateChecks entry at index " + i + ":", item);
            }
          }
        }
      } catch (e) {
        Logger.e("CustomButtonSettings", "Failed to parse stateChecksJson:", e.message);
      }
    }

    Component.onCompleted: {
      root.rootSettings = _settings;
      stateChecksJson = (widgetData && widgetData.stateChecksJson !== undefined) ? widgetData.stateChecksJson : (widgetMetadata && widgetMetadata.stateChecksJson ? widgetMetadata.stateChecksJson : "[]");
      Qt.callLater(populateStateChecks);
    }

    function saveStateChecks() {
      var savedStateChecksArray = [];
      for (var i = 0; i < _settings._stateChecksListModel.count; i++) {
        savedStateChecksArray.push(_settings._stateChecksListModel.get(i));
      }
      _settings.stateChecksJson = JSON.stringify(savedStateChecksArray);

      root.saveSettings({stateChecksJson: _settings.stateChecksJson});
    }
  }

  function saveSettings(fields) {
    if (fields)
      settingsChanged(fields);
  }

  function updateStateCheck(index, command, icon) {
    _settings._stateChecksListModel.set(index, {
                                          "command": command,
                                          "icon": icon
                                        });
    _settings.saveStateChecks();
  }

  function removeStateCheck(index) {
    _settings._stateChecksListModel.remove(index);
    _settings.saveStateChecks();
  }

  function addStateCheck() {
    _settings._stateChecksListModel.append({
                                             "command": "",
                                             "icon": ""
                                           });
    _settings.saveStateChecks();
  }

  RowLayout {
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("common.icon")
      description: I18n.tr("panels.control-center.shortcuts-custom-button-icon-description")
    }

    AtmoIcon {
      Layout.alignment: Qt.AlignVCenter
      icon: _settings.icon || (widgetMetadata && widgetMetadata.icon ? widgetMetadata.icon : "")
      pointSize: Style?.fontSizeXL ?? 24
      visible: (_settings.icon || (widgetMetadata && widgetMetadata.icon ? widgetMetadata.icon : "")) !== ""
    }

    NButton {
      text: I18n.tr("common.browse")
      onClicked: iconPicker.open()
    }
  }

  AtmoIconPicker {
    id: iconPicker
    initialIcon: _settings.icon
    onIconSelected: function (iconName) {
      _settings.icon = iconName;
      saveSettings({icon: _settings.icon});
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.general-tooltip-text-label")
    description: I18n.tr("bar.custom-button.general-tooltip-text-description")
    placeholderText: I18n.tr("placeholders.enter-tooltip")
    text: _settings.generalTooltipText
    onTextEdited: {
      _settings.generalTooltipText = text;
      saveSettings({generalTooltipText: _settings.generalTooltipText});
    }
    defaultValue: widgetMetadata.generalTooltipText
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.show-exec-tooltip-label")
    description: I18n.tr("bar.custom-button.show-exec-tooltip-description")
    checked: _settings.showExecTooltip
    onToggled: checked => {
      _settings.showExecTooltip = checked;
      saveSettings({showExecTooltip: _settings.showExecTooltip});
    }
    defaultValue: widgetMetadata.showExecTooltip
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.left-click-label")
    description: I18n.tr("bar.custom-button.left-click-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onClicked
    onTextEdited: {
      _settings.onClicked = text;
      saveSettings({onClicked: _settings.onClicked});
    }
    defaultValue: widgetMetadata.onClicked
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.right-click-label")
    description: I18n.tr("bar.custom-button.right-click-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onRightClicked
    onTextEdited: {
      _settings.onRightClicked = text;
      saveSettings({onRightClicked: _settings.onRightClicked});
    }
    defaultValue: widgetMetadata.onRightClicked
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("bar.custom-button.middle-click-label")
    description: I18n.tr("bar.custom-button.middle-click-description")
    placeholderText: I18n.tr("placeholders.enter-command")
    text: _settings.onMiddleClicked
    onTextEdited: {
      _settings.onMiddleClicked = text;
      saveSettings({onMiddleClicked: _settings.onMiddleClicked});
    }
    defaultValue: widgetMetadata.onMiddleClicked
  }

  NDivider {}

  NToggle {
    id: enableOnStateLogicToggle
    Layout.fillWidth: true
    label: I18n.tr("panels.control-center.shortcuts-custom-button-enable-on-state-logic-label")
    description: I18n.tr("panels.control-center.shortcuts-custom-button-enable-on-state-logic-description")
    checked: _settings.enableOnStateLogic
    onToggled: checked => {
      _settings.enableOnStateLogic = checked;
      saveSettings({enableOnStateLogic: _settings.enableOnStateLogic});
    }
    defaultValue: widgetMetadata.enableOnStateLogic
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: root.rootSettings && root.rootSettings.enableOnStateLogic
    spacing: Style?.marginM ?? 8

    NLabel {
      label: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-label")
    }

    Repeater {
      model: root.rootSettings ? root.rootSettings._stateChecksListModel : null
      delegate: Item {
        property int currentIndex: index

        implicitHeight: contentRow.implicitHeight
        Layout.fillWidth: true

        RowLayout {
          id: contentRow
          anchors.fill: parent
          spacing: Style?.marginM ?? 8

          NTextInput {
            Layout.fillWidth: true
            placeholderText: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-command")
            text: model.command
            onTextEdited: {
              updateStateCheck(currentIndex, text, model.icon);
            }
          }

          RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Style?.marginS ?? 4

            AtmoIcon {
              icon: model.icon
              pointSize: Style?.fontSizeL ?? 20
              visible: model.icon !== undefined && model.icon !== ""
            }

            AtmoIconButton {
              icon: Icon.folder
              tooltipText: I18n.tr("common.browse")
              baseSize: 24
              onClicked: iconPickerDelegate.open()
            }

            AtmoIconButton {
              icon: Icon.close
              tooltipText: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-remove")
              baseSize: 24
              colorBorder: Qt.alpha(AtmoColor.mOutline, Style.opacityLight)
              colorBg: AtmoColor.mError
              colorFg: AtmoColor.mOnError
              colorBgHover: Qt.alpha(AtmoColor.mError, Style.opacityMedium)
              colorFgHover: AtmoColor.mOnError
              onClicked: {
                removeStateCheck(currentIndex);
              }
            }
          }
        }

        AtmoIconPicker {
          id: iconPickerDelegate
          initialIcon: model.icon
          onIconSelected: function (iconName) {
            updateStateCheck(currentIndex, model.command, iconName);
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style?.marginM ?? 8

      NButton {
        text: I18n.tr("panels.control-center.shortcuts-custom-button-state-checks-add")
        onClicked: addStateCheck()
      }
    }
  }
}
