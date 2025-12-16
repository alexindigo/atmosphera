import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

Item {
  id: root

  // Required properties from parent (set by DesktopWidgets.qml loader)
  property ShellScreen screen
  property var widgetData: null
  property int widgetIndex: -1

  // Optional customization
  property real defaultX: 100
  property real defaultY: 100

  // Content slot - allows natural QML child syntax
  default property alias content: contentContainer.data

  // Exposed state for child content (e.g., to disable shadow during drag)
  readonly property bool isDragging: internal.isDragging
  readonly property bool isScaling: internal.isScaling

  // Whether to show the background container
  property bool showBackground: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

  // Widget size properties
  property real widgetScale: (widgetData && widgetData.scale !== undefined) ? widgetData.scale : 1.0
  property real minScale: 0.5
  property real maxScale: 3.0

  // Scaling sensitivity and threshold constants
  readonly property real scaleSensitivity: 0.0015  // Sensitivity for scaling (scale change per pixel of movement)
  readonly property real scaleUpdateThreshold: 0.015  // Minimum change required to update scale value

  // Internal dragging and scaling state
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
    property real lastScale: 1.0  // Track the last applied scale during scaling operation

    // Global state to manage scaling vs dragging exclusivity
    // When any operation starts (drag or scale), lock the type until operation completes
    property string operationType: ""  // "drag" or "scale" or ""
  }

  // Helper function to update widget data in settings
  function updateWidgetData(properties) {
    if (widgetIndex < 0 || !screen || !screen.name) {
      return; // Early return if necessary data is missing
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

  // Apply scale to the widget from top-left corner
  scale: widgetScale
  transformOrigin: Item.TopLeft
  // Use smooth animation outside edit mode only
  Behavior on scale {
    enabled: !Settings.data.desktopWidgets.editMode
    NumberAnimation {
      duration: 200
      easing.type: Easing.InOutQuad
    }
  }

  // Update base position from widgetData when not dragging
  onWidgetDataChanged: {
    if (!internal.isDragging) {
      internal.baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : defaultX;
      internal.baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : defaultY;
      // Update scale from widgetData if available
      if (widgetData && widgetData.scale !== undefined) {
        widgetScale = widgetData.scale;
      }
    }
  }

  // Edit mode decoration rectangle
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

  // Container with shadow
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

  // Content slot
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
                 // If any operation is already in progress, don't start a new one
                 if (internal.operationType !== "") {
                   return;
                 }

                 pressPos = Qt.point(mouse.x, mouse.y);

                 if (mouse.button === Qt.LeftButton) {
                   // Start dragging
                   internal.operationType = "drag";
                   internal.dragOffsetX = root.x;
                   internal.dragOffsetY = root.y;
                   internal.isDragging = true;
                 } else if (mouse.button === Qt.RightButton) {
                   // Start scaling
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
                           // Calculate the offset from the initial press position
                           var globalPressPos = mapToItem(root.parent, pressPos.x, pressPos.y);
                           var globalCurrentPos = mapToItem(root.parent, mouse.x, mouse.y);

                           // Calculate the movement delta since the press
                           var deltaX = globalCurrentPos.x - globalPressPos.x;
                           var deltaY = globalCurrentPos.y - globalPressPos.y;

                           // Calculate new position based on the original position when drag started
                           var newX = internal.dragOffsetX + deltaX;
                           var newY = internal.dragOffsetY + deltaY;

                           // Boundary clamping - account for scaled widget size
                           var scaledWidth = root.width * root.widgetScale;
                           var scaledHeight = root.height * root.widgetScale;
                           if (root.parent && scaledWidth > 0 && scaledHeight > 0) {
                             newX = Math.max(0, Math.min(newX, root.parent.width - scaledWidth));
                             newY = Math.max(0, Math.min(newY, root.parent.height - scaledHeight));
                           }

                           internal.dragOffsetX = newX;
                           internal.dragOffsetY = newY;
                         } else if (internal.isScaling && pressed && internal.operationType === "scale") {
                           // Calculate relative movement from initial position
                           var dx = mouse.x - internal.initialMousePos.x;
                           var dy = mouse.y - internal.initialMousePos.y;

                           // Calculate combined movement with a more nuanced approach
                           // Use the primary direction of movement to determine scale change
                           var primaryMovement = (Math.abs(dx) > Math.abs(dy)) ? dx : dy;

                           // Calculate scale change based on movement relative to initial widget size
                           // This ensures consistent behavior regardless of current scale level
                           var scaleChange = primaryMovement * root.scaleSensitivity;

                           // Calculate new scale with constraints (adding to last applied scale, not initial scale)
                           var newScale = Math.max(minScale, Math.min(maxScale, internal.lastScale + scaleChange));

                           // Apply smoothing by checking if the change is significant enough
                           // Use a slightly higher threshold to prevent rapid changes
                           if (Math.abs(root.widgetScale - newScale) > root.scaleUpdateThreshold && !isNaN(newScale) && newScale > 0) {
                             root.widgetScale = newScale;
                             internal.lastScale = newScale;
                           }
                         }
                       }

    onReleased: mouse => {
                  if (internal.isDragging && internal.operationType === "drag" && widgetIndex >= 0 && screen && screen.name) {
                    // Update widget position using the helper function
                    root.updateWidgetData({
                                            "x": internal.dragOffsetX,
                                            "y": internal.dragOffsetY
                                          });

                    // Update base position to final position
                    internal.baseX = internal.dragOffsetX;
                    internal.baseY = internal.dragOffsetY;
                    internal.isDragging = false;
                    internal.operationType = "";
                  } else if (internal.isScaling && internal.operationType === "scale") {
                    // Update widget scale using the helper function
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
      internal.lastScale = root.widgetScale;  // Sync lastScale with current scale when operation is canceled
    }
  }
}
