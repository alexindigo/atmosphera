import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

Item {
  id: root

  property ShellScreen screen
  property var widgetData: null
  property int widgetIndex: -1

  property real defaultX: 100
  property real defaultY: 100

  default property alias content: contentContainer.data

  readonly property bool isDragging: internal.isDragging
  readonly property bool isScaling: internal.isScaling

  property bool showBackground: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

  property real widgetScale: (widgetData && widgetData.scale !== undefined) ? widgetData.scale : 1.0
  property real minScale: 0.5
  property real maxScale: 3.0

  readonly property real scaleSensitivity: 0.0015
  readonly property real scaleUpdateThreshold: 0.015

  // Grid size ensures lines pass through screen center on both axes
  readonly property int gridSize: {
    if (!screen)
      return 30;
    var baseSize = Math.round(screen.width * 0.015);
    baseSize = Math.max(20, Math.min(60, baseSize));

    var centerX = screen.width / 2;
    var centerY = screen.height / 2;
    var bestSize = baseSize;
    var bestDistance = Infinity;

    for (var offset = -10; offset <= 10; offset++) {
      var candidate = baseSize + offset;
      if (candidate < 20 || candidate > 60)
        continue;

      var remainderX = centerX % candidate;
      var remainderY = centerY % candidate;

      if (remainderX === 0 && remainderY === 0) {
        return candidate;
      }

      var distance = Math.abs(remainderX) + Math.abs(remainderY);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSize = candidate;
      }
    }

    var gcd = function (a, b) {
      while (b !== 0) {
        var temp = b;
        b = a % b;
        a = temp;
      }
      return a;
    };

    var centerGcd = gcd(Math.round(centerX), Math.round(centerY));
    if (centerGcd > 0) {
      for (var divisor = Math.floor(centerGcd / 60); divisor <= Math.ceil(centerGcd / 20); divisor++) {
        if (centerGcd % divisor !== 0)
          continue;
        var candidate = centerGcd / divisor;
        if (candidate >= 20 && candidate <= 60) {
          if (Math.abs(candidate - baseSize) < Math.abs(bestSize - baseSize)) {
            bestSize = candidate;
          }
        }
      }
    }

    return bestSize;
  }

  QtObject {
    id: internal
    property bool isDragging: false
    property bool isScaling: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property real baseX: (root.widgetData && root.widgetData.x !== undefined) ? root.widgetData.x : root.defaultX
    property real baseY: (root.widgetData && root.widgetData.y !== undefined) ? root.widgetData.y : root.defaultY
    property real initialWidth: 0
    property real initialHeight: 0
    property point initialMousePos: Qt.point(0, 0)
    property real initialScale: 1.0
    property real lastScale: 1.0
    // Locks operation type to prevent switching between drag/scale mid-operation
    property string operationType: ""  // "drag" or "scale" or ""
  }

  function snapToGrid(coord) {
    if (!Settings.data.desktopWidgets.gridSnap) {
      return coord;
    }
    return Math.round(coord / root.gridSize) * root.gridSize;
  }

  function updateWidgetData(properties) {
    if (widgetIndex < 0 || !screen || !screen.name) {
      return;
    }

    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();

    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === screen.name) {
        var widgets = (newMonitorWidgets[i].widgets || []).slice();
        if (widgetIndex < widgets.length) {
          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], properties);
          newMonitorWidgets[i] = Object.assign({}, newMonitorWidgets[i], {
                                                 "widgets": widgets
                                               });
          Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
        }
        break;
      }
    }
  }

  x: internal.isDragging ? internal.dragOffsetX : internal.baseX
  y: internal.isDragging ? internal.dragOffsetY : internal.baseY

  // Scale from top-left corner to prevent position drift
  scale: widgetScale
  transformOrigin: Item.TopLeft

  onWidgetDataChanged: {
    if (!internal.isDragging) {
      internal.baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : defaultX;
      internal.baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : defaultY;
      if (widgetData && widgetData.scale !== undefined) {
        widgetScale = widgetData.scale;
      }
    }
  }

  Rectangle {
    id: decorationRect
    anchors.fill: parent
    anchors.margins: -Style.marginS
    color: Settings.data.desktopWidgets.editMode ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1) : Color.transparent
    border.color: (Settings.data.desktopWidgets.editMode || internal.isDragging) ? (internal.isDragging ? Color.mOutline : Color.mPrimary) : Color.transparent
    border.width: Settings.data.desktopWidgets.editMode ? 3 : (internal.isDragging ? 2 : 0)
    radius: Style.radiusL + Style.marginS
    z: -1
  }

  Rectangle {
    id: container
    anchors.fill: parent
    radius: Style.radiusL
    color: Color.mSurface
    border {
      width: 1
      color: Qt.alpha(Color.mOutline, 0.12)
    }
    clip: true
    visible: root.showBackground

    layer.enabled: Settings.data.general.enableShadows && !internal.isDragging && root.showBackground
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowBlur: Style.shadowBlur * 1.5
      shadowOpacity: Style.shadowOpacity * 0.6
      shadowColor: Color.black
      shadowHorizontalOffset: Settings.data.general.shadowOffsetX
      shadowVerticalOffset: Settings.data.general.shadowOffsetY
      blurMax: Style.shadowBlurMax
    }
  }

  Item {
    id: contentContainer
    anchors.fill: parent
    z: 1
  }

  // Drag and Scale MouseArea - handles both dragging (left-click) and scaling (right-click)
  MouseArea {
    id: interactionArea
    anchors.fill: parent
    z: 1000
    visible: Settings.data.desktopWidgets.editMode
    cursorShape: {
      if (internal.isDragging)
        return Qt.ClosedHandCursor;
      if (internal.isScaling)
        return Qt.SizeAllCursor;
      // Change cursor based on which button user is likely to press
      // Right mouse button for scaling, left for dragging
      return Qt.OpenHandCursor;
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    property point pressPos: Qt.point(0, 0)
    property real initialScale: 1.0

    onPressed: mouse => {
                 // Prevent starting new operation if one is already in progress
                 if (internal.operationType !== "") {
                   return;
                 }

                 pressPos = Qt.point(mouse.x, mouse.y);

                 if (mouse.button === Qt.LeftButton) {
                   internal.operationType = "drag";
                   internal.dragOffsetX = root.x;
                   internal.dragOffsetY = root.y;
                   internal.isDragging = true;
                 } else if (mouse.button === Qt.RightButton) {
                   internal.operationType = "scale";
                   internal.isScaling = true;
                   internal.initialWidth = root.width;
                   internal.initialHeight = root.height;
                   internal.initialMousePos = Qt.point(mouse.x, mouse.y);
                   internal.initialScale = root.widgetScale;
                   internal.lastScale = root.widgetScale;
                 }
               }

    onPositionChanged: mouse => {
                         if (internal.isDragging && pressed && internal.operationType === "drag") {
                           var globalPressPos = mapToItem(root.parent, pressPos.x, pressPos.y);
                           var globalCurrentPos = mapToItem(root.parent, mouse.x, mouse.y);

                           var deltaX = globalCurrentPos.x - globalPressPos.x;
                           var deltaY = globalCurrentPos.y - globalPressPos.y;

                           // Calculate new position based on original position when drag started
                           var newX = internal.dragOffsetX + deltaX;
                           var newY = internal.dragOffsetY + deltaY;

                           // Boundary clamping - must account for scaled widget size
                           var scaledWidth = root.width * root.widgetScale;
                           var scaledHeight = root.height * root.widgetScale;
                           if (root.parent && scaledWidth > 0 && scaledHeight > 0) {
                             newX = Math.max(0, Math.min(newX, root.parent.width - scaledWidth));
                             newY = Math.max(0, Math.min(newY, root.parent.height - scaledHeight));
                           }

                           if (Settings.data.desktopWidgets.gridSnap) {
                             newX = root.snapToGrid(newX);
                             newY = root.snapToGrid(newY);
                             // Re-clamp after snapping to ensure widget stays within bounds
                             if (root.parent && scaledWidth > 0 && scaledHeight > 0) {
                               newX = Math.max(0, Math.min(newX, root.parent.width - scaledWidth));
                               newY = Math.max(0, Math.min(newY, root.parent.height - scaledHeight));
                             }
                           }

                           internal.dragOffsetX = newX;
                           internal.dragOffsetY = newY;
                         } else if (internal.isScaling && pressed && internal.operationType === "scale") {
                           var dx = mouse.x - internal.initialMousePos.x;
                           var dy = mouse.y - internal.initialMousePos.y;

                           // Use primary direction of movement to determine scale change
                           var primaryMovement = (Math.abs(dx) > Math.abs(dy)) ? dx : dy;

                           // Scale change relative to initial widget size ensures consistent behavior
                           var scaleChange = primaryMovement * root.scaleSensitivity;

                           // Add to last applied scale (not initial) to allow smooth continuous scaling
                           var newScale = Math.max(minScale, Math.min(maxScale, internal.lastScale + scaleChange));

                           // Apply smoothing threshold to prevent rapid changes
                           if (Math.abs(root.widgetScale - newScale) > root.scaleUpdateThreshold && !isNaN(newScale) && newScale > 0) {
                             root.widgetScale = newScale;
                             internal.lastScale = newScale;
                           }
                         }
                       }

    onReleased: mouse => {
                  if (internal.isDragging && internal.operationType === "drag" && widgetIndex >= 0 && screen && screen.name) {
                    root.updateWidgetData({
                                            "x": internal.dragOffsetX,
                                            "y": internal.dragOffsetY
                                          });

                    internal.baseX = internal.dragOffsetX;
                    internal.baseY = internal.dragOffsetY;
                    internal.isDragging = false;
                    internal.operationType = "";
                  } else if (internal.isScaling && internal.operationType === "scale") {
                    root.updateWidgetData({
                                            "scale": root.widgetScale
                                          });

                    internal.isScaling = false;
                    internal.operationType = "";
                    internal.lastScale = root.widgetScale;
                  }
                }

    onCanceled: {
      internal.isDragging = false;
      internal.isScaling = false;
      internal.operationType = "";
      // Sync lastScale when operation is canceled to prevent drift
      internal.lastScale = root.widgetScale;
    }
  }
}
