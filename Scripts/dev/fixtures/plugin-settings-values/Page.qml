import QtQuick
import qs.Widgets

Column {
  id: root
  required property var pluginApi
  readonly property bool settingsDirty: false
  readonly property var flagField: pluginApi.field("flag")
  readonly property var amountField: pluginApi.field("amount")
  readonly property var labelField: pluginApi.field("label")
  readonly property var optionalField: pluginApi.field("optionalLabel")
  readonly property var itemsField: pluginApi.field("items")
  readonly property var recordField: pluginApi.field("record")
  property alias flagControl: flagControl
  property alias amountControl: amountControl
  property alias labelControl: labelControl
  property alias optionalControl: optionalControl
  property alias atomicControl: atomicControl
  property alias resetControl: resetControl
  function saveSettings() {
    pluginApi.saveSettings();
  }
  NPluginSettingsField {
    field: root.flagField
    NToggle {
      id: flagControl
      checked: root.flagField.value
      onToggled: value => root.flagField.set(value)
    }
  }
  NPluginSettingsField {
    field: root.amountField
    NSpinBox {
      id: amountControl
      from: -10
      to: 10
      value: root.amountField.value
      onValueModified: value => root.amountField.set(value)
    }
  }
  NPluginSettingsField {
    field: root.labelField
    NTextInput {
      id: labelControl
      text: root.labelField.value
      onEditCommitted: root.labelField.set(labelControl.text)
    }
  }
  NPluginSettingsField {
    field: root.optionalField
    NTextInput {
      id: optionalControl
      text: root.optionalField.value ?? ""
      onEditCommitted: root.optionalField.set(optionalControl.text)
    }
  }
  NPluginSettingsField {
    field: root.itemsField
    NPluginSettingsField {
      field: root.recordField
      NButton {
        id: atomicControl
        text: "Replace atomic values"
        onClicked: {
          root.itemsField.set(["", "item"]);
          var replacement = root.pluginApi.copyValue(root.recordField.value);
          replacement.flag = false;
          replacement.count = 0;
          root.recordField.set(replacement);
        }
      }
    }
  }
  NButton {
    id: resetControl
    text: "Reset typed fields"
    onClicked: root.pluginApi.resetFields(["flag", "amount", "label", "optionalLabel", "items", "record"])
  }
}
