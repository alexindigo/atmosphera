import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property var widgetData: null
  property int widgetIndex: -1

  readonly property var now: Time.now

  property color textColor: {
    var txtColor = widgetData && widgetData.textColor ? widgetData.textColor : "";
    return (txtColor && txtColor !== "") ? txtColor : Color.mOnSurface;
  }
  property real fontSize: {
    var size = widgetData && widgetData.fontSize ? widgetData.fontSize : 0;
    return (size && size > 0) ? size : Style.fontSizeXXXL * 2.5;
  }
  property real widgetOpacity: (widgetData && widgetData.opacity) ? widgetData.opacity : 1.0
  property bool showSeconds: (widgetData && widgetData.showSeconds !== undefined) ? widgetData.showSeconds : true
  property bool showDate: (widgetData && widgetData.showDate !== undefined) ? widgetData.showDate : true

  property bool isDragging: false
  property real dragOffsetX: 0
  property real dragOffsetY: 0
  property real baseX: (widgetData && widgetData.x !== undefined) ? widgetData.x : 100
  property real baseY: (widgetData && widgetData.y !== undefined) ? widgetData.y : 100

  implicitWidth: contentLayout.implicitWidth + Style.marginXL * 2
  implicitHeight: contentLayout.implicitHeight + Style.marginXL * 2
  width: implicitWidth
  height: implicitHeight

  x: isDragging ? dragOffsetX : baseX
  y: isDragging ? dragOffsetY : baseY
  
  // Update base position from widgetData when not dragging
  onWidgetDataChanged: {
    if (!isDragging) {
      baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : 100;
      baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : 100;
    }
  }
  MouseArea {
    id: dragArea
    anchors.fill: parent
    z: 1000
    enabled: Settings.data.desktopWidgets.editMode
    cursorShape: enabled && isDragging ? Qt.ClosedHandCursor : (enabled ? Qt.OpenHandCursor : Qt.ArrowCursor)
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    
    property point pressPos: Qt.point(0, 0)

    onPressed: mouse => {
      pressPos = Qt.point(mouse.x, mouse.y);
      dragOffsetX = root.x;
      dragOffsetY = root.y;
      isDragging = true;
      // Update base position to current position when starting drag
      baseX = root.x;
      baseY = root.y;
    }

    onPositionChanged: mouse => {
      if (isDragging && pressed) {
        var globalPos = mapToItem(root.parent, mouse.x, mouse.y);
        var newX = globalPos.x - pressPos.x;
        var newY = globalPos.y - pressPos.y;
        
        if (root.parent && root.width > 0 && root.height > 0) {
          newX = Math.max(0, Math.min(newX, root.parent.width - root.width));
          newY = Math.max(0, Math.min(newY, root.parent.height - root.height));
        }
        
        if (root.parent && root.parent.checkCollision && root.parent.checkCollision(root, newX, newY)) {
          return;
        }
        
        dragOffsetX = newX;
        dragOffsetY = newY;
      }
    }

    onReleased: mouse => {
      if (isDragging && widgetIndex >= 0) {
        var widgets = Settings.data.desktopWidgets.widgets.slice();
        if (widgetIndex < widgets.length) {
          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], {
            "x": dragOffsetX,
            "y": dragOffsetY
          });
          Settings.data.desktopWidgets.widgets = widgets;
        }
        // Update base position to final position
        baseX = dragOffsetX;
        baseY = dragOffsetY;
        isDragging = false;
      }
    }

    onCanceled: {
      isDragging = false;
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.marginS
    color: Settings.data.desktopWidgets.editMode ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1) : "transparent"
    border.color: (Settings.data.desktopWidgets.editMode || isDragging) ? (isDragging ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5) : Color.mPrimary) : "transparent"
    border.width: Settings.data.desktopWidgets.editMode ? 3 : (isDragging ? 2 : 0)
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
    visible: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

    layer.enabled: Settings.data.general.enableShadows && !root.isDragging && ((widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true)
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

  ColumnLayout {
    id: contentLayout
    anchors.centerIn: parent
    spacing: Style.marginL
    NClock {
      id: clockDisplay
      Layout.alignment: Qt.AlignHCenter
      now: root.now
      clockStyle: Settings.data.location.analogClockInCalendar ? "analog" : "digital"
      backgroundColor: Color.transparent
      clockColor: textColor
      progressColor: Color.mPrimary
      opacity: root.widgetOpacity
      height: Math.round(fontSize * 1.9)
      width: height
      hoursFontSize: fontSize * 0.6
      minutesFontSize: fontSize * 0.4
    }
  }
}