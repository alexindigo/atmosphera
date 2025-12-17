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
  property string clockStyle: (widgetData && widgetData.clockStyle) ? widgetData.clockStyle : "digital"
  property bool showMonthName: (widgetData && widgetData.showMonthName !== undefined) ? widgetData.showMonthName : true

  readonly property real contentPadding: clockStyle === "minimal" ? Style.marginL : Style.marginXL
  implicitWidth: contentLoader.item ? (contentLoader.item.implicitWidth || contentLoader.item.width || 0) + contentPadding * 2 : 0
  implicitHeight: contentLoader.item ? (contentLoader.item.implicitHeight || contentLoader.item.height || 0) + contentPadding * 2 : 0
  width: implicitWidth
  height: implicitHeight

  Component {
    id: nclockComponent
    NClock {
      now: root.now
      clockStyle: root.clockStyle === "analog" ? "analog" : "digital"
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

  Component {
    id: minimalClockComponent
    ColumnLayout {
      spacing: Style.marginXS
      opacity: root.widgetOpacity

      NText {
        text: {
          var timeFormat = Settings.data.location.use12hourFormat ? "hh:mm AP" : "HH:mm";
          return I18n.locale.toString(root.now, timeFormat);
        }
        pointSize: Style.fontSizeXXL
        font.weight: Style.fontWeightBold
        color: clockTextColor
        family: Settings.data.ui.fontFixed
        Layout.alignment: Qt.AlignHCenter
      }

      NText {
        text: {
          if (root.showMonthName) {
            return I18n.locale.toString(root.now, "d MMMM yyyy");
          } else {
            // Format with month number: "17 12 2025"
            var day = root.now.getDate();
            var month = root.now.getMonth() + 1; // getMonth() is 0-based
            var year = root.now.getFullYear();
            return I18n.locale.toString(root.now, "d") + " " + month.toString() + " " + year.toString();
          }
        }
        pointSize: Style.fontSizeM
        font.weight: Style.fontWeightMedium
        color: clockTextColor
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }

  Loader {
    id: contentLoader
    anchors.centerIn: parent
    z: 2
    sourceComponent: clockStyle === "minimal" ? minimalClockComponent : nclockComponent
  }
}
