import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

// Compact circular statistic display using Layout management
Rectangle {
  id: root

  property real value: 0 // 0..100 (or any range visually mapped)
  property string icon: ""
  property string suffix: "%"
  // When nested inside a parent group (NBox), you can make it flat
  property bool flat: false
  // Scales the internal content (labels, gauge, icon) without changing the
  // outer width/height footprint of the component
  property real contentScale: 1.0

  width: 68
  height: 92
  color: flat ? Color.transparent : Color.mSurface
  radius: Style.radiusS
  border.color: flat ? Color.transparent : Color.mSurfaceVariant
  border.width: flat ? 0 : Math.max(1, Style.borderS)

  // Repaint gauge when the bound value changes
  onValueChanged: gauge.requestPaint()

  ColumnLayout {
    id: mainLayout
    anchors.fill: parent
    anchors.margins: Style.marginS * contentScale
    spacing: 0

    // Main gauge container
    Item {
      id: gaugeContainer
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.alignment: Qt.AlignCenter
      Layout.preferredWidth: 68 * contentScale
      Layout.preferredHeight: 68 * contentScale

      Canvas {
        id: gauge
        anchors.fill: parent
        renderStrategy: Canvas.Immediate

        onPaint: {
          const ctx = getContext("2d")
          const w = width, h = height
          const cx = w / 2, cy = h / 2
          const r = Math.min(w, h) / 2 - 5 * contentScale

          // Rotated 90° to the right: gap at the bottom
          // Start at 150° and end at 390° (30°) → bottom opening
          const start = Math.PI * 5 / 6 // 150°
          const endBg = Math.PI * 13 / 6 // 390° (equivalent to 30°)

          ctx.reset()
          ctx.lineWidth = 6 * contentScale

          // Track uses surface for stronger contrast
          ctx.strokeStyle = Color.mSurface
          ctx.beginPath()
          ctx.arc(cx, cy, r, start, endBg)
          ctx.stroke()

          // Value arc with gradient starting at 25%
          const ratio = Math.max(0, Math.min(1, root.value / 100))
          const end = start + (endBg - start) * ratio

          // Calculate gradient start point (25% into the arc)
          const gradientStartRatio = 0.25
          const gradientStart = start + (endBg - start) * gradientStartRatio

          // Create linear gradient
          const startX = cx + r * Math.cos(gradientStart)
          const startY = cy + r * Math.sin(gradientStart)
          const endX = cx + r * Math.cos(endBg)
          const endY = cy + r * Math.sin(endBg)

          const gradient = ctx.createLinearGradient(startX, startY, endX, endY)
          gradient.addColorStop(0, Color.mPrimary)
          gradient.addColorStop(1, Color.mOnSurface)

          ctx.strokeStyle = gradient
          ctx.beginPath()
          ctx.arc(cx, cy, r, start, end)
          ctx.stroke()
        }
      }

      // Percent centered in the circle
      NText {
        id: valueLabel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -4 * contentScale
        text: `${root.value}${root.suffix}`
        pointSize: Style.fontSizeM * contentScale * 0.9
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        horizontalAlignment: Text.AlignHCenter
      }

      NIcon {
        id: iconText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: valueLabel.bottom
        anchors.topMargin: 8 * contentScale
        icon: root.icon
        color: Color.mPrimary
        pointSize: Style.fontSizeM
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
