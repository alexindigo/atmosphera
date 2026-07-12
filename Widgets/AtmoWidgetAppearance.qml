import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.marginL

  // Inbound values
  property real blendStrength: 1.0
  property real blendStrengthDefault: 1.0
  property real hueAdjustment: 0.0
  property real hueAdjustmentDefault: 0.0
  property real contentPadding: 0.0
  property real contentPaddingDefault: 0.0

  // Outbound signals
  signal blendStrengthChanged(real value)
  signal hueAdjustmentChanged(real value)
  signal contentPaddingChanged(real value)

  NHeader {
    label: I18n.tr("panels.desktop-widgets.icon-colorize-title")
    description: I18n.tr("panels.desktop-widgets.icon-colorize-description")
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.icon-blend-strength-label")
    description: I18n.tr("panels.desktop-widgets.icon-blend-strength-description")
    from: 0
    to: 1
    stepSize: 0.05
    showReset: true
    value: root.blendStrength
    defaultValue: root.blendStrengthDefault
    onMoved: v => root.blendStrengthChanged(v)
    text: Math.round(root.blendStrength * 100) + "%"
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.icon-hue-adjustment-label")
    description: I18n.tr("panels.desktop-widgets.icon-hue-adjustment-description")
    from: -180
    to: 180
    stepSize: 5
    showReset: true
    value: root.hueAdjustment
    defaultValue: root.hueAdjustmentDefault
    onMoved: v => root.hueAdjustmentChanged(v)
    text: (root.hueAdjustment > 0 ? "+" : "") + root.hueAdjustment + "°"
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.widget-content-padding-label")
    description: I18n.tr("panels.desktop-widgets.widget-content-padding-description")
    from: 0
    to: 48
    stepSize: 2
    showReset: true
    value: root.contentPadding
    defaultValue: root.contentPaddingDefault
    onMoved: v => root.contentPaddingChanged(v)
    text: Math.round(root.contentPadding) + "px"
  }
}
