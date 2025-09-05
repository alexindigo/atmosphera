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

  sizeRatio: 0.8
  icon: Settings.data.notifications.doNotDisturb ? "notifications_off" : "notifications"
  tooltipText: Settings.data.notifications.doNotDisturb ? "Notification history (Do Not Disturb ON)\nRight-click to toggle Do Not Disturb" : "Notification history\nRight-click to toggle Do Not Disturb"
  colorBg: Color.mSurfaceVariant
  colorFg: Settings.data.notifications.doNotDisturb ? Color.mError : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  onClicked: PanelService.getPanel("notificationHistoryPanel")?.toggle(screen, this)

  onRightClicked: {
    Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
    ToastService.showNotice(
          Settings.data.notifications.doNotDisturb ? "Do Not Disturb enabled" : "Do Not Disturb disabled",
          Settings.data.notifications.doNotDisturb ? "Notifications will be hidden but saved to history" : "Notifications will be shown normally",
          "notice", false, 2000)
  }
}
