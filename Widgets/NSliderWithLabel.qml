import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

RowLayout {
  id: root

  // Properties that mirror NSlider
  property real from: 0
  property real to: 1
  property real value: 0
  property real stepSize: 0.01
  property var cutoutColor
  property bool snapAlways: true
  property real heightRatio: 0.75
  property bool showPercentage: true
  property string suffix: "%"
  property int decimalPlaces: 0 // 0 for integers, 1 for one decimal place, etc.

  // Signals
  signal moved(real value)
  signal pressedChanged(bool pressed)

  spacing: Style.marginS * scaling

  NSlider {
    id: slider
    Layout.fillWidth: true
    from: root.from
    to: root.to
    value: root.value
    stepSize: root.stepSize
    cutoutColor: root.cutoutColor
    snapAlways: root.snapAlways
    heightRatio: root.heightRatio
    stableWidth: true
    minWidth: 200 * scaling

    onMoved: root.moved(value)
    onPressedChanged: root.pressedChanged(pressed)
  }

  NText {
    id: percentageLabel
    visible: root.showPercentage
    text: {
      if (root.decimalPlaces === 0) {
        return Math.round(slider.value * 100) + root.suffix
      } else {
        return (slider.value * 100).toFixed(root.decimalPlaces) + root.suffix
      }
    }
    Layout.alignment: Qt.AlignVCenter
    Layout.leftMargin: Style.marginS * scaling
    Layout.preferredWidth: 50 * scaling
    horizontalAlignment: Text.AlignRight
  }
}
