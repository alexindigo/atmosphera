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
  property color textColor: Color.mOnSurface

  // Content slot - allows natural QML child syntax
  default property alias content: contentContainer.data

  // Exposed state for child content (e.g., to disable shadow during drag)
  readonly property bool isDragging: internal.isDragging

  // Whether to show the background container
  property bool showBackground: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

  // Internal dragging state
  QtObject {
    id: internal
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property real baseX: (root.widgetData && root.widgetData.x !== undefined) ? root.widgetData.x : root.defaultX
    property real baseY: (root.widgetData && root.widgetData.y !== undefined) ? root.widgetData.y : root.defaultY
  }

  x: internal.isDragging ? internal.dragOffsetX : internal.baseX
  y: internal.isDragging ? internal.dragOffsetY : internal.baseY

  // Update base position from widgetData when not dragging
  onWidgetDataChanged: {
    if (!internal.isDragging) {
      internal.baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : defaultX;
      internal.baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : defaultY;
    }
  }

  // Edit mode decoration rectangle
  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.marginS
    color: Settings.data.desktopWidgets.editMode ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1) : "transparent"
    border.color: (Settings.data.desktopWidgets.editMode || internal.isDragging) ? (internal.isDragging ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5) : Color.mPrimary) : "transparent"
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

  // Drag MouseArea - blocks all interaction in edit mode
  MouseArea {
    id: dragArea
    anchors.fill: parent
    z: 1000
    visible: Settings.data.desktopWidgets.editMode
    cursorShape: internal.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons

    property point pressPos: Qt.point(0, 0)

    onPressed: mouse => {
                 pressPos = Qt.point(mouse.x, mouse.y);
                 internal.dragOffsetX = root.x;
                 internal.dragOffsetY = root.y;
                 internal.isDragging = true;
                 // Update base position to current position when starting drag
                 internal.baseX = root.x;
                 internal.baseY = root.y;
               }

    onPositionChanged: mouse => {
                         if (internal.isDragging && pressed) {
                           var globalPos = mapToItem(root.parent, mouse.x, mouse.y);
                           var newX = globalPos.x - pressPos.x;
                           var newY = globalPos.y - pressPos.y;

                           // Boundary clamping
                           if (root.parent && root.width > 0 && root.height > 0) {
                             newX = Math.max(0, Math.min(newX, root.parent.width - root.width));
                             newY = Math.max(0, Math.min(newY, root.parent.height - root.height));
                           }

                           // Collision detection (if parent provides checkCollision function)
                           if (root.parent && root.parent.checkCollision && root.parent.checkCollision(root, newX, newY)) {
                             return;
                           }

                           internal.dragOffsetX = newX;
                           internal.dragOffsetY = newY;
                         }
                       }

    onReleased: mouse => {
                  if (internal.isDragging && widgetIndex >= 0 && screen && screen.name) {
                    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
                    var newMonitorWidgets = monitorWidgets.slice();
                    for (var i = 0; i < newMonitorWidgets.length; i++) {
                      if (newMonitorWidgets[i].name === screen.name) {
                        var widgets = (newMonitorWidgets[i].widgets || []).slice();
                        if (widgetIndex < widgets.length) {
                          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], {
                                                                 "x": internal.dragOffsetX,
                                                                 "y": internal.dragOffsetY
                                                               });
                          newMonitorWidgets[i] = Object.assign({}, newMonitorWidgets[i], {
                                                                 "widgets": widgets
                                                               });
                          Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
                        }
                        break;
                      }
                    }
                    // Update base position to final position
                    internal.baseX = internal.dragOffsetX;
                    internal.baseY = internal.dragOffsetY;
                    internal.isDragging = false;
                  }
                }

    onCanceled: {
      internal.isDragging = false;
    }
  }
}
