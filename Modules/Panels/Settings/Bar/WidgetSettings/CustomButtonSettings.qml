import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Bar orientation (per-screen)
  property bool barIsVertical: (Settings.getBarPositionForScreen(screen?.name) === "left" || Settings.getBarPositionForScreen(screen?.name) === "right")

  property string valueIcon: widgetData.icon !== undefined ? widgetData.icon : widgetMetadata.icon
  property string valueIconPosition: widgetData.iconPosition !== undefined ? widgetData.iconPosition : widgetMetadata.iconPosition
  property bool valueTextStream: widgetData.textStream !== undefined ? widgetData.textStream : widgetMetadata.textStream
  property bool valueParseJson: widgetData.parseJson !== undefined ? widgetData.parseJson : widgetMetadata.parseJson
  property int valueMaxTextLengthHorizontal: widgetData?.maxTextLength?.horizontal ?? widgetMetadata?.maxTextLength?.horizontal
  property int valueMaxTextLengthVertical: widgetData?.maxTextLength?.vertical ?? widgetMetadata?.maxTextLength?.vertical
  property string valueHideMode: (widgetData.hideMode !== undefined) ? widgetData.hideMode : widgetMetadata.hideMode
  property bool valueShowIcon: (widgetData.showIcon !== undefined) ? widgetData.showIcon : widgetMetadata.showIcon
  property bool valueShowExecTooltip: widgetData.showExecTooltip !== undefined ? widgetData.showExecTooltip : widgetMetadata.showExecTooltip
  property bool valueShowTextTooltip: widgetData.showTextTooltip !== undefined ? widgetData.showTextTooltip : widgetMetadata.showTextTooltip
  property string valueColorizeSystemIcon: widgetData.colorizeSystemIcon !== undefined ? widgetData.colorizeSystemIcon : widgetMetadata.colorizeSystemIcon
  property string valueColorizeSystemText: widgetData.colorizeSystemText !== undefined ? widgetData.colorizeSystemText : widgetMetadata.colorizeSystemText
  property string valueIpcIdentifier: widgetData.ipcIdentifier !== undefined ? widgetData.ipcIdentifier : widgetMetadata.ipcIdentifier
  property string valueGeneralTooltipText: widgetData.generalTooltipText !== undefined ? widgetData.generalTooltipText : widgetMetadata.generalTooltipText

  function saveSettings(fields) {
    if (fields)
      settingsChanged(fields);
    else {
      horizontalLengthInput.commitEdit();
      verticalLengthInput.commitEdit();
    }
  }

  function saveTextLength() {
    saveSettings({maxTextLength: Object.assign(Object.create(null), widgetData.maxTextLength || {}, {
      horizontal: valueMaxTextLengthHorizontal, vertical: valueMaxTextLengthVertical
    })});
  }

  NTabBar {
    id: subTabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    distributeEvenly: true
    currentIndex: tabView.currentIndex

    NTabButton {
      text: I18n.tr("bar.custom-button.tab-actions")
      tabIndex: 0
      checked: tabView.currentIndex === 0
      onClicked: tabView.currentIndex = 0
    }
    NTabButton {
      text: I18n.tr("bar.custom-button.tab-icon")
      tabIndex: 1
      checked: tabView.currentIndex === 1
      onClicked: tabView.currentIndex = 1
    }
    NTabButton {
      text: I18n.tr("bar.custom-button.tab-text")
      tabIndex: 2
      checked: tabView.currentIndex === 2
      onClicked: tabView.currentIndex = 2
    }
  }

  NTabView {
    id: tabView
    Layout.fillWidth: true

    // ============ Actions Tab ============
    ColumnLayout {
      spacing: Style.marginM

      RowLayout {
        spacing: Style.marginM

        NTextInput {
          id: leftClickExecInput
          Layout.fillWidth: true
          label: I18n.tr("bar.custom-button.left-click-label")
          description: I18n.tr("bar.custom-button.left-click-description")
          placeholderText: I18n.tr("placeholders.enter-command")
          text: widgetData?.leftClickExec || widgetMetadata.leftClickExec
          onTextEdited: saveSettings({leftClickExec: text})
          defaultValue: widgetMetadata.leftClickExec
        }

        NToggle {
          id: leftClickUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(leftClickUpdateText, I18n.tr("bar.custom-button.left-click-update-text"))
          onExited: TooltipService.hide()
          checked: widgetData?.leftClickUpdateText ?? widgetMetadata.leftClickUpdateText
          onToggled: isChecked => {
            checked = isChecked;
            saveSettings({leftClickUpdateText: isChecked});
          }
          defaultValue: widgetMetadata.leftClickUpdateText
        }
      }

      RowLayout {
        spacing: Style.marginM

        NTextInput {
          id: rightClickExecInput
          Layout.fillWidth: true
          label: I18n.tr("bar.custom-button.right-click-label")
          description: I18n.tr("bar.custom-button.right-click-description")
          placeholderText: I18n.tr("placeholders.enter-command")
          text: widgetData?.rightClickExec || widgetMetadata.rightClickExec
          onTextEdited: saveSettings({rightClickExec: text})
          defaultValue: widgetMetadata.rightClickExec
        }

        NToggle {
          id: rightClickUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(rightClickUpdateText, I18n.tr("bar.custom-button.right-click-update-text"))
          onExited: TooltipService.hide()
          checked: widgetData?.rightClickUpdateText ?? widgetMetadata.rightClickUpdateText
          onToggled: isChecked => {
            checked = isChecked;
            saveSettings({rightClickUpdateText: isChecked});
          }
          defaultValue: widgetMetadata.rightClickUpdateText
        }
      }

      RowLayout {
        spacing: Style.marginM

        NTextInput {
          id: middleClickExecInput
          Layout.fillWidth: true
          label: I18n.tr("bar.custom-button.middle-click-label")
          description: I18n.tr("bar.custom-button.middle-click-description")
          placeholderText: I18n.tr("placeholders.enter-command")
          text: widgetData?.middleClickExec || widgetMetadata.middleClickExec
          onTextEdited: saveSettings({middleClickExec: text})
          defaultValue: widgetMetadata.middleClickExec
        }

        NToggle {
          id: middleClickUpdateText
          enabled: !valueTextStream
          Layout.alignment: Qt.AlignRight | Qt.AlignBottom
          Layout.bottomMargin: Style.marginS
          onEntered: TooltipService.show(middleClickUpdateText, I18n.tr("bar.custom-button.middle-click-update-text"))
          onExited: TooltipService.hide()
          checked: widgetData?.middleClickUpdateText ?? widgetMetadata.middleClickUpdateText
          onToggled: isChecked => {
            checked = isChecked;
            saveSettings({middleClickUpdateText: isChecked});
          }
          defaultValue: widgetMetadata.middleClickUpdateText
        }
      }

      NToggle {
        id: separateWheelToggle
        Layout.fillWidth: true
        label: I18n.tr("bar.custom-button.wheel-mode-separate-label")
        description: I18n.tr("bar.custom-button.wheel-mode-separate-description")
        property bool internalChecked: (widgetData?.wheelMode || widgetMetadata?.wheelMode) === "separate"
        checked: internalChecked
        onToggled: checked => {
          internalChecked = checked;
          saveSettings({wheelMode: checked ? "separate" : "unified"});
        }
        defaultValue: widgetMetadata.wheelMode === "separate"
      }

      ColumnLayout {
        Layout.fillWidth: true

        RowLayout {
          id: unifiedWheelLayout
          visible: !separateWheelToggle.checked
          spacing: Style.marginM

          NTextInput {
            id: wheelExecInput
            Layout.fillWidth: true
            label: I18n.tr("bar.custom-button.wheel-label")
            description: I18n.tr("bar.custom-button.wheel-description")
            placeholderText: I18n.tr("placeholders.enter-command")
            text: widgetData?.wheelExec || widgetMetadata?.wheelExec
            onTextEdited: saveSettings({wheelExec: text})
            defaultValue: widgetMetadata.wheelExec
          }

          NToggle {
            id: wheelUpdateText
            enabled: !valueTextStream
            Layout.alignment: Qt.AlignRight | Qt.AlignBottom
            Layout.bottomMargin: Style.marginS
            onEntered: TooltipService.show(wheelUpdateText, I18n.tr("bar.custom-button.wheel-update-text"))
            onExited: TooltipService.hide()
            checked: widgetData?.wheelUpdateText ?? widgetMetadata?.wheelUpdateText
            onToggled: isChecked => {
              checked = isChecked;
              saveSettings({wheelUpdateText: isChecked});
            }
            defaultValue: widgetMetadata.wheelUpdateText
          }
        }

        ColumnLayout {
          id: separatedWheelLayout
          Layout.fillWidth: true
          visible: separateWheelToggle.checked

          RowLayout {
            spacing: Style.marginM

            NTextInput {
              id: wheelUpExecInput
              Layout.fillWidth: true
              label: I18n.tr("bar.custom-button.wheel-up-label")
              description: I18n.tr("bar.custom-button.wheel-up-description")
              placeholderText: I18n.tr("placeholders.enter-command")
              text: widgetData?.wheelUpExec || widgetMetadata?.wheelUpExec
              onTextEdited: saveSettings({wheelUpExec: text})
              defaultValue: widgetMetadata.wheelUpExec
            }

            NToggle {
              id: wheelUpUpdateText
              enabled: !valueTextStream
              Layout.alignment: Qt.AlignRight | Qt.AlignBottom
              Layout.bottomMargin: Style.marginS
              onEntered: TooltipService.show(wheelUpUpdateText, I18n.tr("bar.custom-button.wheel-update-text"))
              onExited: TooltipService.hide()
              checked: widgetData?.wheelUpUpdateText ?? widgetMetadata?.wheelUpUpdateText
              onToggled: isChecked => {
                checked = isChecked;
                saveSettings({wheelUpUpdateText: isChecked});
              }
              defaultValue: widgetMetadata.wheelUpUpdateText
            }
          }

          RowLayout {
            spacing: Style.marginM

            NTextInput {
              id: wheelDownExecInput
              Layout.fillWidth: true
              label: I18n.tr("bar.custom-button.wheel-down-label")
              description: I18n.tr("bar.custom-button.wheel-down-description")
              placeholderText: I18n.tr("placeholders.enter-command")
              text: widgetData?.wheelDownExec || widgetMetadata?.wheelDownExec
              onTextEdited: saveSettings({wheelDownExec: text})
              defaultValue: widgetMetadata.wheelDownExec
            }

            NToggle {
              id: wheelDownUpdateText
              enabled: !valueTextStream
              Layout.alignment: Qt.AlignRight | Qt.AlignBottom
              Layout.bottomMargin: Style.marginS
              onEntered: TooltipService.show(wheelDownUpdateText, I18n.tr("bar.custom-button.wheel-update-text"))
              onExited: TooltipService.hide()
              checked: widgetData?.wheelDownUpdateText ?? widgetMetadata?.wheelDownUpdateText
              onToggled: isChecked => {
                checked = isChecked;
                saveSettings({wheelDownUpdateText: isChecked});
              }
              defaultValue: widgetMetadata.wheelDownUpdateText
            }
          }
        }
      }
    }

    // ============ Icon Tab ============
    ColumnLayout {
      spacing: Style.marginM

      NToggle {
        id: showIconToggle
        label: I18n.tr("bar.custom-button.show-icon-label")
        description: I18n.tr("bar.custom-button.show-icon-description")
        checked: valueShowIcon
        onToggled: checked => {
          valueShowIcon = checked;
          saveSettings({showIcon: valueShowIcon});
        }
        visible: textCommandInput.text !== ""
        defaultValue: widgetMetadata.showIcon
      }

      RowLayout {
        spacing: Style.marginM
        visible: valueShowIcon

        NLabel {
          label: I18n.tr("common.icon")
          description: I18n.tr("bar.custom-button.icon-description")
        }

        AtmoIcon {
          Layout.alignment: Qt.AlignVCenter
          icon: valueIcon
          pointSize: Style.fontSizeXL
          visible: valueIcon !== ""
        }

        NButton {
          text: I18n.tr("common.browse")
          onClicked: iconPicker.open()
        }
      }

      AtmoIconPicker {
        id: iconPicker
        initialIcon: valueIcon
        onIconSelected: function (iconName) {
          valueIcon = iconName;
          saveSettings({icon: valueIcon});
        }
      }

      NComboBox {
        id: iconPositionComboBox
        visible: valueShowIcon
        label: I18n.tr("bar.custom-button.icon-position-label")
        description: I18n.tr("bar.custom-button.icon-position-description")
        model: barIsVertical ? [
                                 {
                                   name: I18n.tr("bar.custom-button.icon-position-top"),
                                   key: "left"
                                 },
                                 {
                                   name: I18n.tr("bar.custom-button.icon-position-bottom"),
                                   key: "right"
                                 }
                               ] : [
                                 {
                                   name: I18n.tr("bar.custom-button.icon-position-left"),
                                   key: "left"
                                 },
                                 {
                                   name: I18n.tr("bar.custom-button.icon-position-right"),
                                   key: "right"
                                 }
                               ]
        currentKey: valueIconPosition
        onSelected: key => {
          valueIconPosition = key;
          saveSettings({iconPosition: valueIconPosition});
        }
        defaultValue: widgetMetadata.iconPosition
      }

      NColorChoice {
        label: I18n.tr("common.select-icon-color")
        description: I18n.tr("bar.custom-button.icon-color-selection-description")
        currentKey: valueColorizeSystemIcon
        onSelected: key => {
          valueColorizeSystemIcon = key;
          saveSettings({colorizeSystemIcon: valueColorizeSystemIcon});
        }
        defaultValue: widgetMetadata.colorizeSystemIcon
      }

      NTextInput {
        Layout.fillWidth: true
        label: I18n.tr("bar.custom-button.general-tooltip-text-label")
        description: I18n.tr("bar.custom-button.general-tooltip-text-description")
        placeholderText: I18n.tr("placeholders.enter-tooltip")
        text: valueGeneralTooltipText
        onTextEdited: {
          valueGeneralTooltipText = text;
          saveSettings({generalTooltipText: valueGeneralTooltipText});
        }
        defaultValue: widgetMetadata.generalTooltipText
      }

      NToggle {
        id: showExecTooltipToggle
        label: I18n.tr("bar.custom-button.show-exec-tooltip-label")
        description: I18n.tr("bar.custom-button.show-exec-tooltip-description")
        checked: valueShowExecTooltip
        onToggled: checked => {
          valueShowExecTooltip = checked;
          saveSettings({showExecTooltip: valueShowExecTooltip});
        }
        defaultValue: widgetMetadata.showExecTooltip
      }

      NToggle {
        id: showTextTooltipToggle
        label: I18n.tr("bar.custom-button.show-text-tooltip-label")
        description: I18n.tr("bar.custom-button.show-text-tooltip-description")
        checked: valueShowTextTooltip
        onToggled: checked => {
          valueShowTextTooltip = checked;
          saveSettings({showTextTooltip: valueShowTextTooltip});
        }
        defaultValue: widgetMetadata.showTextTooltip
      }

      NTextInput {
        Layout.fillWidth: true
        label: I18n.tr("bar.custom-button.ipc-identifier-label")
        description: I18n.tr("bar.custom-button.ipc-identifier-description")
        placeholderText: I18n.tr("placeholders.enter-ipc-identifier")
        text: valueIpcIdentifier
        onTextEdited: {
          valueIpcIdentifier = text;
          saveSettings({ipcIdentifier: valueIpcIdentifier});
        }
        defaultValue: widgetMetadata.ipcIdentifier
      }
    }

    // ============ Text Tab ============
    ColumnLayout {
      spacing: Style.marginM

      NColorChoice {
        label: I18n.tr("common.select-text-color")
        description: I18n.tr("bar.custom-button.text-color-selection-description")
        currentKey: valueColorizeSystemText
        onSelected: key => {
          valueColorizeSystemText = key;
          saveSettings({colorizeSystemText: valueColorizeSystemText});
        }
        defaultValue: widgetMetadata.colorizeSystemText
      }

      NSpinBox {
        id: horizontalLengthInput
        label: I18n.tr("bar.custom-button.max-text-length-horizontal-label")
        description: I18n.tr("bar.custom-button.max-text-length-horizontal-description")
        from: 0
        to: 100
        value: valueMaxTextLengthHorizontal
        onValueModified: {
          valueMaxTextLengthHorizontal = value;
          saveTextLength();
        }
        defaultValue: widgetMetadata.maxTextLength.horizontal
      }

      NSpinBox {
        id: verticalLengthInput
        label: I18n.tr("bar.custom-button.max-text-length-vertical-label")
        description: I18n.tr("bar.custom-button.max-text-length-vertical-description")
        from: 0
        to: 100
        value: valueMaxTextLengthVertical
        onValueModified: {
          valueMaxTextLengthVertical = value;
          saveTextLength();
        }
        defaultValue: widgetMetadata.maxTextLength.vertical
      }

      NToggle {
        id: textStreamInput
        label: I18n.tr("bar.custom-button.text-stream-label")
        description: I18n.tr("bar.custom-button.text-stream-description")
        checked: valueTextStream
        onToggled: checked => {
          valueTextStream = checked;
          saveSettings({textStream: valueTextStream});
        }
        defaultValue: widgetMetadata.textStream
      }

      NToggle {
        id: parseJsonInput
        label: I18n.tr("bar.custom-button.parse-json-label")
        description: I18n.tr("bar.custom-button.parse-json-description")
        checked: valueParseJson
        onToggled: checked => {
          valueParseJson = checked;
          saveSettings({parseJson: valueParseJson});
        }
        defaultValue: widgetMetadata.parseJson
      }

      NTextInput {
        id: textCommandInput
        Layout.fillWidth: true
        label: I18n.tr("bar.custom-button.display-command-output-label")
        description: valueTextStream ? I18n.tr("bar.custom-button.display-command-output-stream-description") : I18n.tr("bar.custom-button.display-command-output-description")
        placeholderText: I18n.tr("placeholders.command-example")
        text: widgetData?.textCommand || widgetMetadata.textCommand
        onTextEdited: saveSettings({textCommand: text})
        defaultValue: widgetMetadata.textCommand
      }

      NTextInput {
        id: textCollapseInput
        Layout.fillWidth: true
        visible: valueTextStream
        label: I18n.tr("bar.custom-button.collapse-condition-label")
        description: I18n.tr("bar.custom-button.collapse-condition-description")
        placeholderText: I18n.tr("placeholders.enter-text-to-collapse")
        text: widgetData?.textCollapse || widgetMetadata.textCollapse
        onTextEdited: saveSettings({textCollapse: text})
        defaultValue: widgetMetadata.textCollapse
      }

      NTextInput {
        id: textIntervalInput
        Layout.fillWidth: true
        visible: !valueTextStream
        label: I18n.tr("bar.custom-button.refresh-interval-label")
        description: I18n.tr("bar.custom-button.refresh-interval-description")
        placeholderText: String(widgetMetadata.textIntervalMs)
        text: widgetData && widgetData.textIntervalMs !== undefined ? String(widgetData.textIntervalMs) : ""
        onTextEdited: saveSettings({textIntervalMs: parseInt(text || placeholderText, 10)})
        defaultValue: String(widgetMetadata.textIntervalMs)
      }

      NComboBox {
        id: hideModeComboBox
        label: I18n.tr("bar.custom-button.hide-mode-label")
        description: I18n.tr("bar.custom-button.hide-mode-description")
        model: [
          {
            name: I18n.tr("bar.custom-button.hide-mode-always-expanded"),
            key: "alwaysExpanded"
          },
          {
            name: I18n.tr("bar.custom-button.hide-mode-expand-with-output"),
            key: "expandWithOutput"
          },
          {
            name: I18n.tr("bar.custom-button.hide-mode-max-transparent"),
            key: "maxTransparent"
          }
        ]
        currentKey: valueHideMode
        onSelected: key => {
          valueHideMode = key;
          saveSettings({hideMode: valueHideMode});
        }
        visible: textCommandInput.text !== "" && valueTextStream == true
        defaultValue: widgetMetadata.hideMode
      }
    }
  }
}
