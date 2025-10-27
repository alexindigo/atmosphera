import QtQuick
import qs.Commons

Item {
  id: root
  property color fillColor: Color.mPrimary
  property color strokeColor: Color.mOnSurface
  property int strokeWidth: 0
  property var values: []

  // Minimum signal properties
  property bool showMinimumSignal: false
  property real minimumSignalValue: 0.05 // Default to 5% of height

  // Pre compute horizontal mirroring
  readonly property int valuesCount: values.length
  readonly property int totalBars: valuesCount * 2
  readonly property real barSlotWidth: totalBars > 0 ? width / totalBars : 0

  Repeater {
    model: root.totalBars

    Rectangle {
      // The first half of bars are a mirror image (reversed values array).
      // The second half of bars are in normal order.
      property int valueIndex: index < root.valuesCount ? root.valuesCount - 1 - index // Mirrored half
                                                        : index - root.valuesCount // Normal half

      property real rawAmp: root.values[valueIndex]
      property real amp: (root.showMinimumSignal && rawAmp === 0) ? root.minimumSignalValue : rawAmp

      color: root.fillColor
      border.color: root.strokeColor
      border.width: root.strokeWidth
      antialiasing: true

      width: root.barSlotWidth * 0.5 // Creates a small gap between bars
      height: root.height * amp
      x: index * root.barSlotWidth + (root.barSlotWidth * 0.25)
      y: root.height - height
    }
  }
}
