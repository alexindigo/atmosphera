import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Helpers
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

  ExternalCommandCheck {
    id: externalCommandCheck
    commandText: Settings.data.general.externalLockCommand
    enabled: root.visible && Settings.data.general.lockScreenPlugin === "external"
  }

  NComboBox {
    id: _styleSelector
    Layout.fillWidth: true
    label: I18n.tr("panels.lock-screen.lock-screen-style-label")
    description: I18n.tr("panels.lock-screen.lock-screen-style-description")
    model: {
      var items = [];
      items.push({
                   "key": "external",
                   "name": I18n.tr("panels.lock-screen.lock-screen-style-external")
                 });
      items.push({
                   "key": "",
                   "name": I18n.tr("panels.lock-screen.lock-screen-style-builtin")
                 });
      for (var id in LockScreenRegistry.plugins) {
        if (id === "default")
          continue;
        items.push({
                     "key": id,
                     "name": LockScreenRegistry.pluginNames[id] ?? id
                   });
      }
      return items;
    }
    currentKey: Settings.data.general.lockScreenPlugin
    onSelected: key => Settings.data.general.lockScreenPlugin = key
    defaultValue: Settings.getDefaultValue("general.lockScreenPlugin")
  }

  ColumnLayout {
    Layout.fillWidth: true
    visible: Settings.data.general.lockScreenPlugin === "external"
    spacing: Style.marginL

    NTextInput {
      Layout.fillWidth: true
      label: I18n.tr("panels.lock-screen.behavior-command-label")
      description: I18n.tr("panels.lock-screen.behavior-command-description")
      text: Settings.data.general.externalLockCommand
      placeholderText: "hyprlock"
      onTextChanged: Settings.data.general.externalLockCommand = text
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      objectName: "externalCommandStatus"
      text: {
        switch (externalCommandCheck.state) {
        case "missing":
          return I18n.tr("panels.lock-screen.behavior-command-not-found");
        case "pending":
          return I18n.tr("panels.lock-screen.behavior-command-checking");
        case "error":
          return I18n.tr("panels.lock-screen.behavior-command-check-failed");
        case "unverified":
          return I18n.tr("panels.lock-screen.behavior-command-unverified");
        default:
          return "";
        }
      }
      color: externalCommandCheck.state === "missing" ? "#e53935" : AtmoColor.mOnSurfaceVariant
      font.pointSize: Style.fontSizeXS
      visible: text !== ""
      wrapMode: Text.WordWrap
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: I18n.tr("panels.lock-screen.behavior-command-note")
      color: AtmoColor.mOnSurfaceVariant
      font.pointSize: Style.fontSizeXS
      wrapMode: Text.WordWrap
    }
  }

  NButton {
    text: "Preview"
    icon: Icon.eye
    outlined: true
    onClicked: {
      if (PanelService.lockScreen && !PanelService.lockScreen.active) {
        CompositorService.lock();
      }
    }
  }

  function insertToken(token) {
    if (formatInput.inputItem) {
      var input = formatInput.inputItem;
      var cursorPos = input.cursorPosition;
      var currentText = input.text;
      var newText = currentText.substring(0, cursorPos) + token + currentText.substring(cursorPos);
      input.text = newText + " ";
      input.cursorPosition = cursorPos + token.length + 1;
      input.forceActiveFocus();
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    enabled: Settings.data.general.lockScreenPlugin !== "external"
    spacing: Style.marginL

    NComboBox {
      label: I18n.tr("panels.lock-screen.clock-style-label")
      description: I18n.tr("panels.lock-screen.clock-style-description")
      model: [
        {
          "key": "analog",
          "name": I18n.tr("panels.lock-screen.clock-style-analog")
        },
        {
          "key": "digital",
          "name": I18n.tr("panels.lock-screen.clock-style-digital")
        },
        {
          "key": "custom",
          "name": I18n.tr("panels.lock-screen.clock-style-custom")
        }
      ]
      currentKey: Settings.data.general.clockStyle
      onSelected: key => Settings.data.general.clockStyle = key
      defaultValue: Settings.getDefaultValue("general.clockStyle")
      z: 10
    }

    NTextInput {
      id: formatInput
      label: I18n.tr("panels.lock-screen.clock-format-label")
      description: I18n.tr("panels.lock-screen.clock-format-description")
      text: Settings.data.general.clockFormat
      onTextChanged: Settings.data.general.clockFormat = text
      visible: Settings.data.general.clockStyle === "custom"
      defaultValue: Settings.getDefaultValue("general.clockFormat")
    }

    NDateTimeTokens {
      Layout.fillWidth: true
      Layout.preferredHeight: 300
      visible: Settings.data.general.clockStyle === "custom"
      onTokenClicked: token => root.insertToken(token)
    }

    NToggle {
      label: I18n.tr("panels.lock-screen.password-chars-label")
      description: I18n.tr("panels.lock-screen.password-chars-description")
      checked: Settings.data.general.passwordChars
      onToggled: checked => Settings.data.general.passwordChars = checked
      defaultValue: Settings.getDefaultValue("general.passwordChars")
    }

    NToggle {
      label: I18n.tr("panels.lock-screen.compact-lockscreen-label")
      description: I18n.tr("panels.lock-screen.compact-lockscreen-description")
      checked: Settings.data.general.compactLockScreen
      onToggled: checked => Settings.data.general.compactLockScreen = checked
      defaultValue: Settings.getDefaultValue("general.compactLockScreen")
    }

    NToggle {
      label: I18n.tr("panels.lock-screen.enable-lockscreen-media-controls-label")
      description: I18n.tr("panels.lock-screen.enable-lockscreen-media-controls-description")
      checked: Settings.data.general.enableLockScreenMediaControls
      onToggled: checked => Settings.data.general.enableLockScreenMediaControls = checked
      visible: !Settings.data.general.compactLockScreen
      defaultValue: Settings.getDefaultValue("general.enableLockScreenMediaControls")
    }

    NToggle {
      label: I18n.tr("panels.lock-screen.lock-screen-animations-label")
      description: I18n.tr("panels.lock-screen.lock-screen-animations-description")
      checked: Settings.data.general.lockScreenAnimations
      onToggled: checked => Settings.data.general.lockScreenAnimations = checked
      defaultValue: Settings.getDefaultValue("general.lockScreenAnimations")
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.lock-screen.lock-screen-blur-strength-label")
      description: I18n.tr("panels.lock-screen.lock-screen-blur-strength-description")
      from: 0.0
      to: 1.0
      stepSize: 0.01
      showReset: true
      value: Settings.data.general.lockScreenBlur
      onMoved: value => Settings.data.general.lockScreenBlur = value
      text: ((Settings.data.general.lockScreenBlur) * 100).toFixed(0) + "%"
      defaultValue: Settings.getDefaultValue("general.lockScreenBlur")
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.lock-screen.lock-screen-tint-strength-label")
      description: I18n.tr("panels.lock-screen.lock-screen-tint-strength-description")
      from: 0.0
      to: 1.0
      stepSize: 0.01
      showReset: true
      value: Settings.data.general.lockScreenTint
      onMoved: value => Settings.data.general.lockScreenTint = value
      text: ((Settings.data.general.lockScreenTint) * 100).toFixed(0) + "%"
      defaultValue: Settings.getDefaultValue("general.lockScreenTint")
    }
  }
}
