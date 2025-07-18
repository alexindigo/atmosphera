import QtQuick 
import Quickshell
import Quickshell.Io
import qs.Settings
import qs.Components

Item {
    id: root
    width: 22; height: 22

    // Bell icon/button
    Item {
        id: bell
        width: 22; height: 22
        Text {
            anchors.centerIn: parent
            text: notificationHistoryWin.hasUnread ? "notifications_unread" : "notifications"
            font.family: mouseAreaBell.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
            font.pixelSize: 16
            font.weight: notificationHistoryWin.hasUnread ? Font.Bold : Font.Normal
            color: mouseAreaBell.containsMouse ? Theme.accentPrimary : (notificationHistoryWin.hasUnread ? Theme.accentPrimary : Theme.textDisabled)
        }
        MouseArea {
            id: mouseAreaBell
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: notificationHistoryWin.visible = !notificationHistoryWin.visible
            onEntered: notificationTooltip.tooltipVisible = true
            onExited: notificationTooltip.tooltipVisible = false
        }
    }

    StyledTooltip {
        id: notificationTooltip
        text: "Notification History"
        tooltipVisible: false
        targetItem: bell
        delay: 200
    }
}