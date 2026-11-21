import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

RowLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.marginM

  property string label: ""
  property string description: ""
  property int timeoutValue: 0
  property int defaultValue: 60
  property int rememberedValue: defaultValue
  readonly property bool stageEnabled: timeoutValue > 0
  signal timeoutEdited(int value)

  onTimeoutValueChanged: {
    if (timeoutValue > 0)
      rememberedValue = timeoutValue;
  }

  NSpinBox {
    id: spinBox
    Layout.fillWidth: true
    label: root.label
    description: root.description
    enabled: root.stageEnabled
    from: 1
    to: 86400
    suffix: "s"
    Binding {
      target: spinBox
      property: "value"
      value: root.stageEnabled ? root.timeoutValue : root.rememberedValue
    }
    defaultValue: root.defaultValue
    onValueModified: value => {
      root.rememberedValue = value;
      if (root.stageEnabled)
        root.timeoutEdited(value);
    }
  }

  NToggle {
    Layout.fillWidth: false
    Accessible.name: root.label
    checked: root.stageEnabled
    onToggled: checked => {
      // Settle focused text before disabling the spin box blurs it.
      spinBox.commitEdit();
      root.timeoutEdited(checked ? root.rememberedValue : 0);
    }
  }
}
