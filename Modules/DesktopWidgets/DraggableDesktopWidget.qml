import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Services.Noctalia
import qs.Widgets

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
  readonly property real cornerScaleSensitivity: 0.0003  // Much lower sensitivity for corner handles

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
    property real previousWidth: 0
    property real centerX: baseX + (previousWidth > 0 ? previousWidth / 2 : root.width / 2)
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

  function removeWidget() {
    if (widgetIndex < 0 || !screen || !screen.name) {
      return;
    }

    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();

    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === screen.name) {
        var widgets = (newMonitorWidgets[i].widgets || []).slice();
        if (widgetIndex >= 0 && widgetIndex < widgets.length) {
          widgets.splice(widgetIndex, 1);
          newMonitorWidgets[i] = Object.assign({}, newMonitorWidgets[i], {
                                                 "widgets": widgets
                                               });
          Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
        }
        break;
      }
    }
  }

  function openWidgetSettings() {
    if (!widgetData || !widgetData.id || !screen) {
      return;
    }

    var widgetId = widgetData.id;
    var hasSettings = false;

    // Check if widget has settings
    if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      if (manifest && manifest.entryPoints && manifest.entryPoints.settings) {
        hasSettings = true;
      }
    } else {
      hasSettings = DesktopWidgetRegistry.widgetSettingsMap[widgetId] !== undefined;
    }

    if (!hasSettings) {
      Logger.w("DraggableDesktopWidget", "Widget does not have settings:", widgetId);
      return;
    }

    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (!popupMenuWindow) {
      Logger.e("DraggableDesktopWidget", "No popup menu window found for screen");
      return;
    }

    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml");

    function instantiateAndOpen() {
      var dialog = component.createObject(popupMenuWindow.dialogParent, {
                                            "widgetIndex": widgetIndex,
                                            "widgetData": widgetData,
                                            "widgetId": widgetId,
                                            "sectionId": screen.name
                                          });

      if (dialog) {
        dialog.updateWidgetSettings.connect((sec, idx, settings) => {
                                              root.updateWidgetData(settings);
                                            });
        popupMenuWindow.hasDialog = true;
        dialog.closed.connect(() => {
                                popupMenuWindow.hasDialog = false;
                                popupMenuWindow.close();
                                dialog.destroy();
                              });
        popupMenuWindow.open();
        dialog.open();
      } else {
        Logger.e("DraggableDesktopWidget", "Failed to create widget settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("DraggableDesktopWidget", "Error loading settings dialog component:", component.errorString());
    } else {
      component.statusChanged.connect(() => {
                                      if (component.status === Component.Ready) {
                                        instantiateAndOpen();
                                      } else if (component.status === Component.Error) {
                                        Logger.e("DraggableDesktopWidget", "Error loading settings dialog component:", component.errorString());
                                      }
                                    });
    }
  }

  x: internal.isDragging ? internal.dragOffsetX : internal.baseX
  y: internal.isDragging ? internal.dragOffsetY : internal.baseY

  // Scale from top-left corner to prevent position drift
  scale: widgetScale
  transformOrigin: Item.TopLeft

  // Adjust position when width changes to maintain center position
  onWidthChanged: {
    if (!internal.isDragging && !internal.isScaling && internal.previousWidth > 0 && width > 0) {
      var widthDelta = width - internal.previousWidth;
      // Adjust baseX to keep center position constant
      internal.baseX = internal.baseX - widthDelta / 2;
      internal.centerX = internal.baseX + width / 2;
    }
    internal.previousWidth = width;
  }

  Component.onCompleted: {
    internal.previousWidth = width;
    internal.centerX = internal.baseX + width / 2;
  }

  onWidgetDataChanged: {
    if (!internal.isDragging) {
      internal.baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : defaultX;
      internal.baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : defaultY;
      if (widgetData && widgetData.scale !== undefined) {
        widgetScale = widgetData.scale;
      }
      // Update centerX and previousWidth when widget data changes
      internal.previousWidth = width;
      internal.centerX = internal.baseX + width / 2;
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

  // Context menu for right-click
  NPopupContextMenu {
    id: contextMenu
    visible: false

    property bool hasSettings: {
      if (!widgetData || !widgetData.id) {
        return false;
      }
      var widgetId = widgetData.id;
      if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
        var pluginId = widgetId.replace("plugin:", "");
        var manifest = PluginRegistry.getPluginManifest(pluginId);
        return manifest && manifest.entryPoints && manifest.entryPoints.settings;
      }
      return DesktopWidgetRegistry.widgetSettingsMap[widgetId] !== undefined;
    }

    model: {
      var items = [];
      if (contextMenu.hasSettings) {
        items.push({
                     "label": I18n.tr("context-menu.widget-settings"),
                     "action": "widget-settings",
                     "icon": "settings"
                   });
      }
      items.push({
                   "label": I18n.tr("context-menu.delete"),
                   "action": "delete",
                   "icon": "trash"
                 });
      return items;
    }

    onTriggered: (action, item) => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     root.openWidgetSettings();
                   } else if (action === "delete") {
                     root.removeWidget();
                   }
                 }
  }

  // Drag MouseArea - handles dragging (left-click)
  MouseArea {
    id: dragArea
    anchors.fill: parent
    z: 1000
    visible: Settings.data.desktopWidgets.editMode
    cursorShape: internal.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    property point pressPos: Qt.point(0, 0)

    onPressed: mouse => {
                 // Prevent starting new operation if one is already in progress
                 if (internal.operationType !== "") {
                   return;
                 }

                 pressPos = Qt.point(mouse.x, mouse.y);
                 internal.operationType = "drag";
                 internal.dragOffsetX = root.x;
                 internal.dragOffsetY = root.y;
                 internal.isDragging = true;
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
                    internal.centerX = internal.baseX + root.width / 2;
                    internal.isDragging = false;
                    internal.operationType = "";
                  }
                }

    onCanceled: {
      internal.isDragging = false;
      internal.operationType = "";
    }
  }

  // Right-click MouseArea for context menu
  MouseArea {
    id: contextMenuArea
    anchors.fill: parent
    z: 1001
    visible: Settings.data.desktopWidgets.editMode
    acceptedButtons: Qt.RightButton
    hoverEnabled: true

    onPressed: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.showContextMenu(contextMenu);
                     contextMenu.openAtItem(root, screen);
                   }
                 }
               }
  }

  // Corner handles for scaling
  readonly property real cornerHandleSize: 12
  readonly property real outlineMargin: Style.marginS

  // Top-left corner
  Canvas {
    id: topLeftHandle
    visible: Settings.data.desktopWidgets.editMode && !internal.isDragging
    x: -outlineMargin
    y: -outlineMargin
    width: cornerHandleSize
    height: cornerHandleSize
    z: 2000

    onPaint: {
      var ctx = getContext("2d");
      ctx.reset();
      ctx.fillStyle = Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.7);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(cornerHandleSize, 0);
      ctx.lineTo(0, cornerHandleSize);
      ctx.closePath();
      ctx.fill();
    }

    Component.onCompleted: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.SizeFDiagCursor
      property point pressPos: Qt.point(0, 0)
      property real initialScale: 1.0

      onPressed: mouse => {
                   if (internal.operationType !== "") {
                     return;
                   }
                   pressPos = mapToItem(root.parent, mouse.x, mouse.y);
                   internal.operationType = "scale";
                   internal.isScaling = true;
                   internal.initialScale = root.widgetScale;
                   internal.lastScale = root.widgetScale;
                 }

      onPositionChanged: mouse => {
                           if (internal.isScaling && pressed && internal.operationType === "scale") {
                             var currentPos = mapToItem(root.parent, mouse.x, mouse.y);
                             // Calculate diagonal distance from opposite corner (bottom-right)
                             var oppositeCornerX = root.x + root.width * root.widgetScale;
                             var oppositeCornerY = root.y + root.height * root.widgetScale;
                             var initialDistance = Math.sqrt(
                               Math.pow(pressPos.x - oppositeCornerX, 2) + 
                               Math.pow(pressPos.y - oppositeCornerY, 2)
                             );
                             var currentDistance = Math.sqrt(
                               Math.pow(currentPos.x - oppositeCornerX, 2) + 
                               Math.pow(currentPos.y - oppositeCornerY, 2)
                             );
                             
                             if (initialDistance > 0) {
                               var scaleRatio = currentDistance / initialDistance;
                               var newScale = Math.max(minScale, Math.min(maxScale, internal.initialScale * scaleRatio));
                               
                               if (!isNaN(newScale) && newScale > 0) {
                                 root.widgetScale = newScale;
                                 internal.lastScale = newScale;
                               }
                             }
                           }
                         }

      onReleased: mouse => {
                    if (internal.isScaling && internal.operationType === "scale") {
                      root.updateWidgetData({
                                              "scale": root.widgetScale
                                            });
                      internal.isScaling = false;
                      internal.operationType = "";
                      internal.lastScale = root.widgetScale;
                    }
                  }

      onCanceled: {
        internal.isScaling = false;
        internal.operationType = "";
        internal.lastScale = root.widgetScale;
      }
    }
  }

  // Top-right corner
  Canvas {
    id: topRightHandle
    visible: Settings.data.desktopWidgets.editMode && !internal.isDragging
    x: root.width + outlineMargin - cornerHandleSize
    y: -outlineMargin
    width: cornerHandleSize
    height: cornerHandleSize
    z: 2000

    onPaint: {
      var ctx = getContext("2d");
      ctx.reset();
      ctx.fillStyle = Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.7);
      ctx.beginPath();
      ctx.moveTo(cornerHandleSize, 0);
      ctx.lineTo(cornerHandleSize, cornerHandleSize);
      ctx.lineTo(0, 0);
      ctx.closePath();
      ctx.fill();
    }

    Component.onCompleted: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.SizeBDiagCursor
      property point pressPos: Qt.point(0, 0)
      property real initialScale: 1.0

      onPressed: mouse => {
                   if (internal.operationType !== "") {
                     return;
                   }
                   pressPos = mapToItem(root.parent, mouse.x, mouse.y);
                   internal.operationType = "scale";
                   internal.isScaling = true;
                   internal.initialScale = root.widgetScale;
                   internal.lastScale = root.widgetScale;
                 }

      onPositionChanged: mouse => {
                           if (internal.isScaling && pressed && internal.operationType === "scale") {
                             var currentPos = mapToItem(root.parent, mouse.x, mouse.y);
                             // Calculate diagonal distance from opposite corner (bottom-left)
                             var oppositeCornerX = root.x;
                             var oppositeCornerY = root.y + root.height * root.widgetScale;
                             var initialDistance = Math.sqrt(
                               Math.pow(pressPos.x - oppositeCornerX, 2) + 
                               Math.pow(pressPos.y - oppositeCornerY, 2)
                             );
                             var currentDistance = Math.sqrt(
                               Math.pow(currentPos.x - oppositeCornerX, 2) + 
                               Math.pow(currentPos.y - oppositeCornerY, 2)
                             );
                             
                             if (initialDistance > 0) {
                               var scaleRatio = currentDistance / initialDistance;
                               var newScale = Math.max(minScale, Math.min(maxScale, internal.initialScale * scaleRatio));
                               
                               if (!isNaN(newScale) && newScale > 0) {
                                 root.widgetScale = newScale;
                                 internal.lastScale = newScale;
                               }
                             }
                           }
                         }

      onReleased: mouse => {
                    if (internal.isScaling && internal.operationType === "scale") {
                      root.updateWidgetData({
                                              "scale": root.widgetScale
                                            });
                      internal.isScaling = false;
                      internal.operationType = "";
                      internal.lastScale = root.widgetScale;
                    }
                  }

      onCanceled: {
        internal.isScaling = false;
        internal.operationType = "";
        internal.lastScale = root.widgetScale;
      }
    }
  }

  // Bottom-left corner
  Canvas {
    id: bottomLeftHandle
    visible: Settings.data.desktopWidgets.editMode && !internal.isDragging
    x: -outlineMargin
    y: root.height + outlineMargin - cornerHandleSize
    width: cornerHandleSize
    height: cornerHandleSize
    z: 2000

    onPaint: {
      var ctx = getContext("2d");
      ctx.reset();
      ctx.fillStyle = Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.7);
      ctx.beginPath();
      ctx.moveTo(0, cornerHandleSize);
      ctx.lineTo(0, 0);
      ctx.lineTo(cornerHandleSize, cornerHandleSize);
      ctx.closePath();
      ctx.fill();
    }

    Component.onCompleted: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    Connections {
      target: root
      function onWidthChanged() { if (bottomLeftHandle.visible) bottomLeftHandle.requestPaint() }
      function onHeightChanged() { if (bottomLeftHandle.visible) bottomLeftHandle.requestPaint() }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.SizeBDiagCursor
      property point pressPos: Qt.point(0, 0)
      property real initialScale: 1.0

      onPressed: mouse => {
                   if (internal.operationType !== "") {
                     return;
                   }
                   pressPos = mapToItem(root.parent, mouse.x, mouse.y);
                   internal.operationType = "scale";
                   internal.isScaling = true;
                   internal.initialScale = root.widgetScale;
                   internal.lastScale = root.widgetScale;
                 }

      onPositionChanged: mouse => {
                           if (internal.isScaling && pressed && internal.operationType === "scale") {
                             var currentPos = mapToItem(root.parent, mouse.x, mouse.y);
                             // Calculate diagonal distance from opposite corner (top-right)
                             var oppositeCornerX = root.x + root.width * root.widgetScale;
                             var oppositeCornerY = root.y;
                             var initialDistance = Math.sqrt(
                               Math.pow(pressPos.x - oppositeCornerX, 2) + 
                               Math.pow(pressPos.y - oppositeCornerY, 2)
                             );
                             var currentDistance = Math.sqrt(
                               Math.pow(currentPos.x - oppositeCornerX, 2) + 
                               Math.pow(currentPos.y - oppositeCornerY, 2)
                             );
                             
                             if (initialDistance > 0) {
                               var scaleRatio = currentDistance / initialDistance;
                               var newScale = Math.max(minScale, Math.min(maxScale, internal.initialScale * scaleRatio));
                               
                               if (!isNaN(newScale) && newScale > 0) {
                                 root.widgetScale = newScale;
                                 internal.lastScale = newScale;
                               }
                             }
                           }
                         }

      onReleased: mouse => {
                    if (internal.isScaling && internal.operationType === "scale") {
                      root.updateWidgetData({
                                              "scale": root.widgetScale
                                            });
                      internal.isScaling = false;
                      internal.operationType = "";
                      internal.lastScale = root.widgetScale;
                    }
                  }

      onCanceled: {
        internal.isScaling = false;
        internal.operationType = "";
        internal.lastScale = root.widgetScale;
      }
    }
  }

  // Bottom-right corner
  Canvas {
    id: bottomRightHandle
    visible: Settings.data.desktopWidgets.editMode && !internal.isDragging
    x: root.width + outlineMargin - cornerHandleSize
    y: root.height + outlineMargin - cornerHandleSize
    width: cornerHandleSize
    height: cornerHandleSize
    z: 2000

    onPaint: {
      var ctx = getContext("2d");
      ctx.reset();
      ctx.fillStyle = Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.7);
      ctx.beginPath();
      ctx.moveTo(cornerHandleSize, cornerHandleSize);
      ctx.lineTo(cornerHandleSize, 0);
      ctx.lineTo(0, cornerHandleSize);
      ctx.closePath();
      ctx.fill();
    }

    Component.onCompleted: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    Connections {
      target: root
      function onWidthChanged() { if (bottomRightHandle.visible) bottomRightHandle.requestPaint() }
      function onHeightChanged() { if (bottomRightHandle.visible) bottomRightHandle.requestPaint() }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.SizeFDiagCursor
      property point pressPos: Qt.point(0, 0)
      property real initialScale: 1.0

      onPressed: mouse => {
                   if (internal.operationType !== "") {
                     return;
                   }
                   pressPos = mapToItem(root.parent, mouse.x, mouse.y);
                   internal.operationType = "scale";
                   internal.isScaling = true;
                   internal.initialScale = root.widgetScale;
                   internal.lastScale = root.widgetScale;
                 }

      onPositionChanged: mouse => {
                           if (internal.isScaling && pressed && internal.operationType === "scale") {
                             var currentPos = mapToItem(root.parent, mouse.x, mouse.y);
                             // Calculate diagonal distance from opposite corner (top-left)
                             var oppositeCornerX = root.x;
                             var oppositeCornerY = root.y;
                             var initialDistance = Math.sqrt(
                               Math.pow(pressPos.x - oppositeCornerX, 2) + 
                               Math.pow(pressPos.y - oppositeCornerY, 2)
                             );
                             var currentDistance = Math.sqrt(
                               Math.pow(currentPos.x - oppositeCornerX, 2) + 
                               Math.pow(currentPos.y - oppositeCornerY, 2)
                             );
                             
                             if (initialDistance > 0) {
                               var scaleRatio = currentDistance / initialDistance;
                               var newScale = Math.max(minScale, Math.min(maxScale, internal.initialScale * scaleRatio));
                               
                               if (!isNaN(newScale) && newScale > 0) {
                                 root.widgetScale = newScale;
                                 internal.lastScale = newScale;
                               }
                             }
                           }
                         }

      onReleased: mouse => {
                    if (internal.isScaling && internal.operationType === "scale") {
                      root.updateWidgetData({
                                              "scale": root.widgetScale
                                            });
                      internal.isScaling = false;
                      internal.operationType = "";
                      internal.lastScale = root.widgetScale;
                    }
                  }

      onCanceled: {
        internal.isScaling = false;
        internal.operationType = "";
        internal.lastScale = root.widgetScale;
      }
    }
  }
}
