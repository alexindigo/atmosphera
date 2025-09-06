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
  tooltipText: Settings.data.notifications.doNotDisturb ? "Notification history.\nRight-click to disable 'Do Not Disturb'." : "Notification history.\nRight-click to enable 'Do Not Disturb'."
  colorBg: Color.mSurfaceVariant
  colorFg: Settings.data.notifications.doNotDisturb ? Color.mError : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  onClicked: PanelService.getPanel("notificationHistoryPanel")?.toggle(screen, this)

  onRightClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
}
