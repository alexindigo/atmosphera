import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  // Public properties
  property string text: ""
  property bool checked: false
  property int tabIndex: 0
  property real pointSize: Style.fontSizeM
  property bool isFirst: false
  property bool isLast: false
  // Internal state
  property bool isHovered: false
  // Styling
  property color fillColor: root.isHovered ? Color.mHover : (root.checked ? Color.mPrimary : Color.mSurface)
  property color borderColor: Color.mOutline
  property real borderWidth: Style.borderS
  property real radius: Style.iRadiusM

  signal clicked

  // Sizing
  Layout.fillHeight: true
  implicitWidth: tabText.implicitWidth + Style.marginM * 2

  onFillColorChanged: canvas.requestPaint()
  onBorderColorChanged: canvas.requestPaint()
  onIsFirstChanged: canvas.requestPaint()
  onIsLastChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);

      var r = root.radius;
      var bw = root.borderWidth;
      var halfBw = bw / 2;

      // Determine corner radii
      var tlr = root.isFirst ? r : 0; // top-left
      var blr = root.isFirst ? r : 0; // bottom-left
      var trr = root.isLast ? r : 0; // top-right
      var brr = root.isLast ? r : 0; // bottom-right

      // Draw inset for border
      var x = halfBw;
      var y = halfBw;
      var w = width - bw;
      var h = height - bw;

      ctx.beginPath();
      // Start at top-left after the corner
      ctx.moveTo(x + tlr, y);
      // Top edge to top-right corner
      ctx.lineTo(x + w - trr, y);
      // Top-right corner
      if (trr > 0)
        ctx.arcTo(x + w, y, x + w, y + trr, trr);
      else
        ctx.lineTo(x + w, y);
      // Right edge to bottom-right corner
      ctx.lineTo(x + w, y + h - brr);
      // Bottom-right corner
      if (brr > 0)
        ctx.arcTo(x + w, y + h, x + w - brr, y + h, brr);
      else
        ctx.lineTo(x + w, y + h);
      // Bottom edge to bottom-left corner
      ctx.lineTo(x + blr, y + h);
      // Bottom-left corner
      if (blr > 0)
        ctx.arcTo(x, y + h, x, y + h - blr, blr);
      else
        ctx.lineTo(x, y + h);
      // Left edge to top-left corner
      ctx.lineTo(x, y + tlr);
      // Top-left corner
      if (tlr > 0)
        ctx.arcTo(x, y, x + tlr, y, tlr);
      else
        ctx.lineTo(x, y);
      ctx.closePath();

      // Fill
      ctx.fillStyle = root.fillColor;
      ctx.fill();

      // Stroke
      ctx.strokeStyle = root.borderColor;
      ctx.lineWidth = bw;
      ctx.stroke();
    }
  }

  Behavior on fillColor {
    ColorAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  NText {
    id: tabText
    y: Style.pixelAlignCenter(parent.height, height)
    anchors {
      left: parent.left
      right: parent.right
      leftMargin: Style.marginS
      rightMargin: Style.marginS
    }
    text: root.text
    pointSize: root.pointSize
    font.weight: Style.fontWeightSemiBold
    color: root.isHovered ? Color.mOnHover : (root.checked ? Color.mOnPrimary : Color.mOnSurface)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.isHovered = true
    onExited: root.isHovered = false
    onClicked: {
      root.clicked();
      // Update parent NTabBar's currentIndex
      if (root.parent && root.parent.parent && root.parent.parent.currentIndex !== undefined) {
        root.parent.parent.currentIndex = root.tabIndex;
      }
    }
  }
}
