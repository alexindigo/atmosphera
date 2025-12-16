import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var now: Time.now

  property color clockTextColor: {
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

  implicitWidth: contentLayout.implicitWidth + Style.marginXL * 2
  implicitHeight: contentLayout.implicitHeight + Style.marginXL * 2
  width: implicitWidth
  height: implicitHeight

  ColumnLayout {
    id: contentLayout
    anchors.centerIn: parent
    spacing: Style.marginL
    z: 2

    NClock {
      id: clockDisplay
      Layout.alignment: Qt.AlignHCenter
      now: root.now
      clockStyle: Settings.data.location.analogClockInCalendar ? "analog" : "digital"
      backgroundColor: Color.transparent
      clockColor: clockTextColor
      progressColor: Color.mPrimary
      opacity: root.widgetOpacity
      height: Math.round(fontSize * 1.9)
      width: height
      hoursFontSize: fontSize * 0.6
      minutesFontSize: fontSize * 0.4
    }
  }
}
