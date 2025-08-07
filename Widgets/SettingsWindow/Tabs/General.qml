import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings

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
            text: "Profile"
            font.pixelSize: 18
            font.bold: true
            color: Theme.textPrimary
            Layout.bottomMargin: 8
        }

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            Text {
                text: "Profile Image"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                text: "Your profile picture displayed in various places throughout the shell"
                font.pixelSize: 12
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.bottomMargin: 4
            }

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: 24
                        border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                        border.width: 2
                        z: 2
                    }

                    Avatar {
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 16
                    color: Theme.surfaceVariant
                    border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1

                    TextInput {
                        id: profileImageInput

                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        text: Settings.settings.profileImage
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                        onTextChanged: {
                            Settings.settings.profileImage = text;
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: profileImageInput.forceActiveFocus()
                        }

                    }

                }

            }

        }

    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 26
        Layout.bottomMargin: 18
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    ColumnLayout {
        spacing: 4
        Layout.fillWidth: true

        Text {
            text: "User Interface"
            font.pixelSize: 18
            font.bold: true
            color: Theme.textPrimary
            Layout.bottomMargin: 8
        }

        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show Corners"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display rounded corners"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                }

                Rectangle {
                    id: cornersSwitch

                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showCorners ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showCorners ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: cornersThumb

                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showCorners ? cornersSwitch.width - width - 2 : 2

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
                            Settings.settings.showCorners = !Settings.settings.showCorners;
                        }
                    }

                }

            }

        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 4

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Show Dock"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Display a dock at the bottom of the screen for quick access to applications"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                }

                Rectangle {
                    id: dockSwitch

                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.showDock ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.showDock ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: dockThumb

                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.showDock ? dockSwitch.width - width - 2 : 2

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
                            Settings.settings.showDock = !Settings.settings.showDock;
                        }
                    }

                }

            }

        }

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 4

            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: "Dim Desktop"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Text {
                        text: "Dim the desktop when panels or menus are open"
                        font.pixelSize: 12
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                }

                Rectangle {
                    id: dimSwitch

                    width: 52
                    height: 32
                    radius: 16
                    color: Settings.settings.dimPanels ? Theme.accentPrimary : Theme.surfaceVariant
                    border.color: Settings.settings.dimPanels ? Theme.accentPrimary : Theme.outline
                    border.width: 2

                    Rectangle {
                        id: dimThumb

                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.outline
                        border.width: 1
                        y: 2
                        x: Settings.settings.dimPanels ? dimSwitch.width - width - 2 : 2

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
                            Settings.settings.dimPanels = !Settings.settings.dimPanels;
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
