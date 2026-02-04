import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Battery widget with Android 16 style rendering (horizontal or vertical)
Item {
  id: root

  // Data (must be provided by parent)
  required property real percentage
  required property bool charging
  required property bool pluggedIn
  required property bool ready

  // Sizing - baseSize controls overall scaleFactor for bar/panel usage
  property real baseSize: Style.fontSizeM

  // Styling - no hardcoded colors, only theme colors
  readonly property color baseColor: Color.mOnSurface
  readonly property color lowColor: Color.mError
  readonly property color chargingColor: Color.mPrimary

  property bool isLow: false
  property bool isCharging: false

  // Display options
  property bool showPercentageText: true
  property bool vertical: false

  // Alternating state icon display (toggles between percentage and icon when charging/plugged)
  property bool showStateIcon: false

  onHasStateIconChanged: {
    if (!hasStateIcon) showStateIcon = false
  }

  // Internal sizing calculations based on baseSize
  readonly property real scaleFactor: baseSize / Style.fontSizeM
  readonly property real bodyWidth: Style.toOdd(22 * scaleFactor)
  readonly property real bodyHeight: Style.toOdd(14 * scaleFactor)
  readonly property real terminalWidth: Math.round(2.5 * scaleFactor)
  readonly property real terminalHeight: Math.round(7 * scaleFactor)
  readonly property real cornerRadius: Math.round(3 * scaleFactor)

  // Total size is just body + terminal (no external icon)
  readonly property real totalWidth: vertical ? bodyHeight : bodyWidth + terminalWidth
  readonly property real totalHeight: vertical ? bodyWidth + terminalWidth : bodyHeight

  // Determine active color based on state
  readonly property color activeColor: {
    if (!ready) {
      return Qt.alpha(baseColor, Style.opacityMedium);
    }
    if (isCharging) {
      return chargingColor;
    }
    if (isLowBattery) {
      return lowColor;
    }
    return baseColor;
  }

  // Background color for empty portion (semi-transparent)
  readonly property color emptyColor: Qt.alpha(Color.mOnSurface, 0.6)

  // State icon logic
  readonly property bool hasStateIcon: charging || pluggedIn
  readonly property string stateIcon: {
    if (charging) return "bolt-filled";
    if (pluggedIn) return "plug-filled"
    return "";
  }

  // Animated percentage for smooth transitions
  property real animatedPercentage: percentage

  Behavior on animatedPercentage {
    enabled: !Settings.data.general.animationDisabled
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  // Repaint when animated percentage changes (throttled)
  onAnimatedPercentageChanged: {
    if (!repaintTimer.running) {
      repaintTimer.start();
    }
  }
  onActiveColorChanged: batteryCanvas.requestPaint()
  onEmptyColorChanged: batteryCanvas.requestPaint()
  onVerticalChanged: batteryCanvas.requestPaint()

  // Throttle timer to limit repaint frequency (~30 FPS)
  Timer {
    id: repaintTimer
    interval: 33
    repeat: true
    onTriggered: {
      batteryCanvas.requestPaint();
      // Stop once animation settles
      if (Math.abs(root.animatedPercentage - root.percentage) < 0.5) {
        stop();
      }
    }
  }

  // Timer to alternate between percentage text and state icon when charging/plugged
  Timer {
    id: alternateTimer
    interval: 3000
    repeat: true
    running: root.hasStateIcon && root.ready
    onTriggered: root.showStateIcon = !root.showStateIcon
  }

  implicitWidth: Math.round(totalWidth)
  implicitHeight: Math.round(totalHeight)
  Layout.maximumWidth: implicitWidth
  Layout.maximumHeight: implicitHeight

  Canvas {
    id: batteryCanvas
    width: root.vertical ? root.bodyHeight : root.bodyWidth + root.terminalWidth
    height: root.vertical ? root.bodyWidth + root.terminalWidth : root.bodyHeight
    anchors.left: root.vertical ? undefined : parent.left
    anchors.bottom: root.vertical ? parent.bottom : undefined
    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

    // Optimized Canvas settings for better GPU performance
    renderStrategy: Canvas.Cooperative
    renderTarget: Canvas.FramebufferObject

    // Enable layer caching
    layer.enabled: true
    layer.smooth: true

    Component.onCompleted: {
      requestPaint();
    }

    onPaint: {
      const ctx = getContext("2d");

      ctx.reset();

      const bodyW = root.bodyWidth;
      const bodyH = root.bodyHeight;
      const termW = root.terminalWidth;
      const termH = root.terminalHeight;
      const radius = root.cornerRadius;
      const isVertical = root.vertical;

      if (isVertical) {
        // Vertical: body is rotated (width becomes height)
        // Terminal at top, fill from bottom to top
        const vBodyW = bodyH;  // swapped
        const vBodyH = bodyW;  // swapped

        // Draw battery body background
        ctx.fillStyle = root.emptyColor;
        ctx.beginPath();
        roundedRect(ctx, 0, termW, vBodyW, vBodyH, radius);
        ctx.fill();

        // Draw terminal cap at the top (centered)
        const termX = (vBodyW - termH) / 2;
        ctx.beginPath();
        roundedRect(ctx, termX, 0, termH, termW, radius / 2);
        ctx.fill();

        // Draw fill based on percentage (bottom to top)
        const pct = Math.max(0, Math.min(100, root.animatedPercentage));
        if (pct > 0 && root.ready) {
          const fillH = vBodyH * (pct / 100);
          const fillY = termW + vBodyH - fillH;

          ctx.fillStyle = root.activeColor;
          ctx.beginPath();
          roundedRect(ctx, 0, fillY, vBodyW, fillH, radius);
          ctx.fill();
        }
      } else {
        // Horizontal: original drawing logic
        // Draw battery body background (semi-transparent empty portion)
        ctx.fillStyle = root.emptyColor;
        ctx.beginPath();
        roundedRect(ctx, 0, 0, bodyW, bodyH, radius);
        ctx.fill();

        // Draw terminal cap on the right (semi-transparent)
        const termX = bodyW;
        const termY = (bodyH - termH) / 2;
        ctx.beginPath();
        roundedRect(ctx, termX, termY, termW, termH, radius / 2);
        ctx.fill();

        // Draw fill based on percentage (left to right, no padding)
        const pct = Math.max(0, Math.min(100, root.animatedPercentage));
        if (pct > 0 && root.ready) {
          const fillW = bodyW * (pct / 100);

          ctx.fillStyle = root.activeColor;
          ctx.beginPath();
          roundedRect(ctx, 0, 0, fillW, bodyH, radius);
          ctx.fill();
        }
      }
    }

    // Helper function to draw rounded rectangle
    function roundedRect(ctx, x, y, w, h, r) {
      if (w < 2 * r) r = w / 2;
      if (h < 2 * r) r = h / 2;
      ctx.moveTo(x + r, y);
      ctx.lineTo(x + w - r, y);
      ctx.arcTo(x + w, y, x + w, y + r, r);
      ctx.lineTo(x + w, y + h - r);
      ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
      ctx.lineTo(x + r, y + h);
      ctx.arcTo(x, y + h, x, y + h - r, r);
      ctx.lineTo(x, y + r);
      ctx.arcTo(x, y, x + r, y, r);
      ctx.closePath();
    }
  }

  // Percentage text overlaid on battery center
  NText {
    id: percentageText
    visible: root.showPercentageText && root.ready && !root.showStateIcon
    x: batteryCanvas.x + Style.pixelAlignCenter(batteryCanvas.width, width)
    y: batteryCanvas.y + Style.pixelAlignCenter(batteryCanvas.height, height)
    font.family: Settings.data.ui.fontFixed
    font.weight: Style.fontWeightBold
    text: Math.round(root.animatedPercentage)
    pointSize: Style.toOdd(root.baseSize * 0.83)
    color: Qt.alpha(Color.mSurface, 0.75)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  // State icon centered inside battery body (shown when alternating)
  NIcon {
    id: stateIconOverlay
    visible: root.hasStateIcon && root.showStateIcon
    x: batteryCanvas.x + Style.pixelAlignCenter(batteryCanvas.width, width)
    y: batteryCanvas.y + Style.pixelAlignCenter(batteryCanvas.height, height)
    icon: root.stateIcon
    pointSize: Style.toOdd(root.baseSize)
    color: Qt.alpha(Color.mSurface, 0.75)
  }
}
