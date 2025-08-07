import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Components
import qs.Helpers
import qs.Services
import qs.Settings
import qs.Widgets
import qs.Widgets.LockScreen

Rectangle {
    id: systemWidget

    property string uptimeText: "--:--"
    property bool panelVisible: false
    property var settingsModal: null

    function logout() {
        if (WorkspaceManager.isNiri)
            logoutProcessNiri.running = true;
        else if (WorkspaceManager.isHyprland)
            logoutProcessHyprland.running = true;
        else
            console.warn("No supported compositor detected for logout");
    }

    function suspend() {
        suspendProcess.running = true;
    }

    function shutdown() {
        shutdownProcess.running = true;
    }

    function reboot() {
        rebootProcess.running = true;
    }

    function updateSystemInfo() {
        uptimeProcess.running = true;
    }

    width: 440 * Theme.uiScale
    height: 80 * Theme.uiScale
    color: "transparent"
    anchors.horizontalCenterOffset: -2
    onPanelVisibleChanged: {
        if (panelVisible)
            updateSystemInfo();

    }
    Component.onCompleted: {
        uptimeProcess.running = true;
    }

    Rectangle {
        id: card

        anchors.fill: parent
        color: Theme.surface
        radius: 18 * Theme.uiScale

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18 * Theme.uiScale
            spacing: 12 * Theme.uiScale

            RowLayout {
                Layout.fillWidth: true
                spacing: 12 * Theme.uiScale

                Rectangle {
                    width: 48 * Theme.uiScale
                    height: 48 * Theme.uiScale
                    radius: 24 * Theme.uiScale
                    color: Theme.accentPrimary

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: 24 * Theme.uiScale
                        border.color: Theme.accentPrimary
                        border.width: 2 * Theme.uiScale
                        z: 2
                    }

                    Avatar {
                    }

                }

                ColumnLayout {
                    spacing: 4 * Theme.uiScale
                    Layout.fillWidth: true

                    Text {
                        text: Quickshell.env("USER")
                        font.family: Theme.fontFamily
                        font.pixelSize: 16 * Theme.uiScale
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "System Uptime: " + uptimeText
                        font.family: Theme.fontFamily
                        font.pixelSize: 12 * Theme.uiScale
                        color: Theme.textSecondary
                    }

                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: settingsButton

                    width: 32 * Theme.uiScale
                    height: 32 * Theme.uiScale
                    radius: 16 * Theme.uiScale
                    color: settingsButtonArea.containsMouse || settingsButtonArea.pressed ? Theme.accentPrimary : "transparent"
                    border.color: Theme.accentPrimary
                    border.width: 1 * Theme.uiScale

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -1
                        text: "settings"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16 * Theme.uiScale
                        color: settingsButtonArea.containsMouse || settingsButtonArea.pressed ? Theme.backgroundPrimary : Theme.accentPrimary
                    }

                    MouseArea {
                        id: settingsButtonArea

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            if (typeof settingsModal !== 'undefined' && settingsModal && settingsModal.openSettings)
                                settingsModal.openSettings();
                        }
                    }

                    StyledTooltip {
                        id: settingsTooltip

                        text: "Settings"
                        targetItem: settingsButton
                        tooltipVisible: settingsButtonArea.containsMouse
                    }

                }

                Rectangle {
                    id: systemButton

                    width: 32 * Theme.uiScale
                    height: 32 * Theme.uiScale
                    radius: 16 * Theme.uiScale
                    color: systemButtonArea.containsMouse || systemButtonArea.pressed ? Theme.accentPrimary : "transparent"
                    border.color: Theme.accentPrimary
                    border.width: 1 * Theme.uiScale

                    Text {
                        anchors.centerIn: parent
                        text: "power_settings_new"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16 * Theme.uiScale
                        color: systemButtonArea.containsMouse || systemButtonArea.pressed ? Theme.backgroundPrimary : Theme.accentPrimary
                    }

                    MouseArea {
                        id: systemButtonArea

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            systemMenu.visible = !systemMenu.visible;
                        }
                    }

                    StyledTooltip {
                        id: systemTooltip

                        text: "Power Menu"
                        targetItem: systemButton
                        tooltipVisible: systemButtonArea.containsMouse
                    }

                }

            }

        }

    }

    PanelWithOverlay {
        id: systemMenu

        anchors.top: systemButton.bottom
        anchors.right: systemButton.right

        Rectangle {
            width: 160 * Theme.uiScale
            height: 220 * Theme.uiScale
            color: Theme.surface
            radius: 8 * Theme.uiScale
            border.color: Theme.outline
            border.width: 1 * Theme.uiScale
            visible: true
            z: 9999
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.rightMargin: 32 * Theme.uiScale
            anchors.topMargin: systemButton.y + systemButton.height + 48 * Theme.uiScale

            // Prevent closing when clicking in the panel bg
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8 * Theme.uiScale
                spacing: 4 * Theme.uiScale

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36 * Theme.uiScale
                    radius: 6 * Theme.uiScale
                    color: lockButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12 * Theme.uiScale
                        spacing: 8 * Theme.uiScale

                        Text {
                            text: "lock_outline"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16 * Theme.uiScale
                            color: lockButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                        }

                        Text {
                            text: "Lock Screen"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14 * Theme.uiScale
                            color: lockButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                            Layout.fillWidth: true
                        }

                    }

                    MouseArea {
                        id: lockButtonArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            lockScreen.locked = true;
                            systemMenu.visible = false;
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36 * Theme.uiScale
                    radius: 6 * Theme.uiScale
                    color: suspendButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12 * Theme.uiScale
                        spacing: 8 * Theme.uiScale

                        Text {
                            text: "bedtime"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16 * Theme.uiScale
                            color: suspendButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                        }

                        Text {
                            text: "Suspend"
                            font.pixelSize: 14 * Theme.uiScale
                            color: suspendButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                            Layout.fillWidth: true
                        }

                    }

                    MouseArea {
                        id: suspendButtonArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            suspend();
                            systemMenu.visible = false;
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36 * Theme.uiScale
                    radius: 6 * Theme.uiScale
                    color: rebootButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12 * Theme.uiScale
                        spacing: 8 * Theme.uiScale

                        Text {
                            text: "refresh"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16 * Theme.uiScale
                            color: rebootButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                        }

                        Text {
                            text: "Reboot"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14 * Theme.uiScale
                            color: rebootButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                            Layout.fillWidth: true
                        }

                    }

                    MouseArea {
                        id: rebootButtonArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            reboot();
                            systemMenu.visible = false;
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36 * Theme.uiScale
                    radius: 6 * Theme.uiScale
                    color: logoutButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12 * Theme.uiScale
                        spacing: 8 * Theme.uiScale

                        Text {
                            text: "exit_to_app"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16 * Theme.uiScale
                            color: logoutButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                        }

                        Text {
                            text: "Logout"
                            font.pixelSize: 14 * Theme.uiScale
                            color: logoutButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                            Layout.fillWidth: true
                        }

                    }

                    MouseArea {
                        id: logoutButtonArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            logout();
                            systemMenu.visible = false;
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36 * Theme.uiScale
                    radius: 6 * Theme.uiScale
                    color: shutdownButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12 * Theme.uiScale
                        spacing: 8 * Theme.uiScale

                        Text {
                            text: "power_settings_new"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16 * Theme.uiScale
                            color: shutdownButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                        }

                        Text {
                            text: "Shutdown"
                            font.pixelSize: 14 * Theme.uiScale
                            color: shutdownButtonArea.containsMouse ? Theme.onAccent : Theme.textPrimary
                            Layout.fillWidth: true
                        }

                    }

                    MouseArea {
                        id: shutdownButtonArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            shutdown();
                            systemMenu.visible = false;
                        }
                    }

                }

            }

        }

    }

    Process {
        id: uptimeProcess

        command: ["sh", "-c", "uptime | awk -F 'up ' '{print $2}' | awk -F ',' '{print $1}' | xargs"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                uptimeText = this.text.trim();
                uptimeProcess.running = false;
            }
        }

    }

    Process {
        id: shutdownProcess

        command: ["shutdown", "-h", "now"]
        running: false
    }

    Process {
        id: rebootProcess

        command: ["reboot"]
        running: false
    }

    Process {
        id: suspendProcess

        command: ["systemctl", "suspend"]
        running: false
    }

    Process {
        id: logoutProcessNiri

        command: ["niri", "msg", "action", "quit", "--skip-confirmation"]
        running: false
    }

    Process {
        id: logoutProcessHyprland

        command: ["hyprctl", "dispatch", "exit"]
        running: false
    }

    Process {
        id: logoutProcess

        command: ["loginctl", "terminate-user", Quickshell.env("USER")]
        running: false
    }

    Timer {
        interval: 60000
        repeat: true
        running: panelVisible
        onTriggered: updateSystemInfo()
    }

    LockScreen {
        id: lockScreen
    }

}
