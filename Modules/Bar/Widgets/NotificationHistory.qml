import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetSettings: {
    var section = barSection.replace("Section", "").toLowerCase()
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool userShowUnreadBadge: (widgetSettings.showUnreadBadge !== undefined) ? widgetSettings.showUnreadBadge : BarWidgetRegistry.widgetMetadata["NotificationHistory"].showUnreadBadge
  readonly property bool userHideWhenZero: (widgetSettings.hideWhenZero !== undefined) ? widgetSettings.hideWhenZero : BarWidgetRegistry.widgetMetadata["NotificationHistory"].hideWhenZero
  readonly property bool userDoNotDisturb: (widgetSettings.doNotDisturb !== undefined) ? widgetSettings.doNotDisturb : BarWidgetRegistry.widgetMetadata["NotificationHistory"].doNotDisturb

  function lastSeenTs() {
    return widgetSettings.lastSeenTs || 0
  }

  function computeUnreadCount() {
    var since = lastSeenTs()
    var count = 0
    var model = NotificationService.historyModel
    for (var i = 0; i < model.count; i++) {
      var item = model.get(i)
      var ts = item.timestamp instanceof Date ? item.timestamp.getTime() : item.timestamp
      if (ts > since)
        count++
    }
    return count
  }

  sizeRatio: 0.8
  icon: (Settings.data.notifications.doNotDisturb || userDoNotDisturb) ? "notifications_off" : "notifications"
  tooltipText: (Settings.data.notifications.doNotDisturb
                || userDoNotDisturb) ? "Notification history.\nRight-click to disable 'Do Not Disturb'." : "Notification history.\nRight-click to enable 'Do Not Disturb'."
  colorBg: Color.mSurfaceVariant
  colorFg: (Settings.data.notifications.doNotDisturb || userDoNotDisturb) ? Color.mError : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  onClicked: {
    // Open first using current geometry as anchor
    var panel = PanelService.getPanel("notificationHistoryPanel")
    panel?.toggle(screen, this)
    // Update last seen right after to avoid affecting anchor calculation
    Qt.callLater(function () {
      try {
        var section = barSection.replace("Section", "").toLowerCase()
        if (section && sectionWidgetIndex >= 0) {
          var widgets = Settings.data.bar.widgets[section]
          if (widgets && sectionWidgetIndex < widgets.length) {
            widgets[sectionWidgetIndex].lastSeenTs = Time.timestamp * 1000
          }
        }
      } catch (e) {

      }
    })
  }

  onRightClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb

  Loader {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: -4 * scaling
    anchors.topMargin: -4 * scaling
    z: 2
    active: userShowUnreadBadge && (!userHideWhenZero || computeUnreadCount() > 0)
    sourceComponent: Rectangle {
      width: 16 * scaling
      height: 16 * scaling
      radius: width / 2
      color: Color.mError
      border.color: Color.mSurface
      border.width: 1
      visible: computeUnreadCount() > 0 || !userHideWhenZero
      NText {
        anchors.centerIn: parent
        text: Math.min(computeUnreadCount(), 9)
        font.pointSize: Style.fontSizeXXS * scaling
        color: Color.mOnError
      }
    }
  }
}
