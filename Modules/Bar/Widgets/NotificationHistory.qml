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
    return Settings.data.notifications?.lastSeenTs || 0
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
    var panel = PanelService.getPanel("notificationHistoryPanel")
    panel?.toggle(screen, this)
    Settings.data.notifications.lastSeenTs = Time.timestamp * 1000
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
      id: badge
      readonly property int count: computeUnreadCount()
      readonly property string label: count <= 99 ? String(count) : "99+"
      readonly property real pad: 8 * scaling
      height: 16 * scaling
      width: Math.max(height, textNode.implicitWidth + pad)
      radius: height / 2
      color: Color.mError
      border.color: Color.mSurface
      border.width: 1
      visible: count > 0 || !userHideWhenZero
      NText {
        id: textNode
        anchors.centerIn: parent
        text: badge.label
        font.pointSize: Style.fontSizeXXS * scaling
        color: Color.mOnError
      }
    }
  }
}
