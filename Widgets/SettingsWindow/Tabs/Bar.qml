import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Settings
import qs.Components

ColumnLayout {
    id: root
    spacing: 0
    anchors.fill: parent
    anchors.margins: 0

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
    }


    ColumnLayout {
        spacing: 4
        Layout.fillWidth: true

        Text {
            text: "Elements"
            font.pixelSize: 18
            font.bold: true
            color: Theme.textPrimary
            Layout.bottomMargin: 8
        }


        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show Active Window Icon"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display the icon of the currently focused window in the bar"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: activeWindowIconSwitch
                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showActiveWindowIcon ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showActiveWindowIcon ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: activeWindowIconThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showActiveWindowIcon ? activeWindowIconSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Settings.settings.showActiveWindowIcon = !Settings.settings.showActiveWindowIcon;
                        }
                    }
                }
            }
        }


        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show Active Window"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display the title of the currently focused window below the bar"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: activeWindowSwitch
                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showActiveWindow ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showActiveWindow ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: activeWindowThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showActiveWindow ? activeWindowSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Settings.settings.showActiveWindow = !Settings.settings.showActiveWindow;
                        }
                    }
                }
            }
        }


        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show System Info"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display system information (CPU, RAM, etc.) in the bar"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: systemInfoSwitch
                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showSystemInfoInBar ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showSystemInfoInBar ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: systemInfoThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showSystemInfoInBar ? systemInfoSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Settings.settings.showSystemInfoInBar = !Settings.settings.showSystemInfoInBar;
                        }
                    }
                }
            }
        }


        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show Taskbar"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display a taskbar showing currently open windows"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: taskbarSwitch
                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showTaskbar ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showTaskbar ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: taskbarThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showTaskbar ? taskbarSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Settings.settings.showTaskbar = !Settings.settings.showTaskbar;
                        }
                    }
                }
            }
        }


        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 8

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show Media"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display media controls and information in the bar"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    id: mediaSwitch
                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showMediaInBar ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showMediaInBar ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: mediaThumb
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showMediaInBar ? mediaSwitch.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Settings.settings.showMediaInBar = !Settings.settings.showMediaInBar;
                        }
                    }
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }
}