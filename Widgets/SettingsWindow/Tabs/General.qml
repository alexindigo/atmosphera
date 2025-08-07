import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings

ScrollView {
    anchors.fill: parent
    padding: 0
    rightPadding: 12
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    
    ColumnLayout {
        id: root
        width: parent.availableWidth
        spacing: 0 * Theme.uiScale
        anchors.top: parent.top
        anchors.margins: 0 * Theme.uiScale

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 0
        }



        ColumnLayout {
            spacing: 4 * Theme.uiScale
            Layout.fillWidth: true

            Text {
                text: "Profile"
                font.pixelSize: 18 * Theme.uiScale
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 8
            }

            ColumnLayout {
                spacing: 2 * Theme.uiScale
                Layout.fillWidth: true

                Text {
                    text: "Profile Image"
                    font.pixelSize: 13 * Theme.uiScale
                    font.bold: true
                    color: Theme.textPrimary
                }

                Text {
                    text: "Your profile picture displayed in various places throughout the shell"
                    font.pixelSize: 12 * Theme.uiScale
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                }

                RowLayout {
                    spacing: 8 * Theme.uiScale
                    Layout.fillWidth: true

                    Rectangle {
                        width: 48 * Theme.uiScale
                        height: 48 * Theme.uiScale
                        radius: 24 * Theme.uiScale

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: 24 * Theme.uiScale
                            border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                            border.width: 2 * Theme.uiScale
                            z: 2
                        }

                        Avatar {
                        }

                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40 * Theme.uiScale
                        radius: 16 * Theme.uiScale
                        color: Theme.surfaceVariant
                        border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                        border.width: 1 * Theme.uiScale

                        TextInput {
                            id: profileImageInput

                            anchors.fill: parent
                            anchors.leftMargin: 12 * Theme.uiScale
                            anchors.rightMargin: 12 * Theme.uiScale
                            anchors.topMargin: 6 * Theme.uiScale
                            anchors.bottomMargin: 6 * Theme.uiScale
                            text: Settings.settings.profileImage
                            font.pixelSize: 13 * Theme.uiScale
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
            Layout.topMargin: 26 * Theme.uiScale
            Layout.bottomMargin: 18 * Theme.uiScale
            height: 1 * Theme.uiScale
            color: Theme.outline
            opacity: 0.3
        }

        ColumnLayout {
            spacing: 4 * Theme.uiScale
            Layout.fillWidth: true

            Text {
                text: "User Interface"
                font.pixelSize: 18 * Theme.uiScale
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 8
            }

            ColumnLayout {
                spacing: 4 * Theme.uiScale
                Layout.fillWidth: true

                RowLayout {
                    spacing: 8 * Theme.uiScale
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4 * Theme.uiScale
                        Layout.fillWidth: true

                        Text {
                            text: "Show Corners"
                            font.pixelSize: 13 * Theme.uiScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Display rounded corners"
                            font.pixelSize: 12 * Theme.uiScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                    }

                    Rectangle {
                        id: cornersSwitch

                        width: 52 * Theme.uiScale
                        height: 32 * Theme.uiScale
                        radius: 16 * Theme.uiScale
                        color: Settings.settings.showCorners ? Theme.accentPrimary : Theme.surfaceVariant
                        border.color: Settings.settings.showCorners ? Theme.accentPrimary : Theme.outline
                        border.width: 2 * Theme.uiScale

                        Rectangle {
                            id: cornersThumb

                            width: 28 * Theme.uiScale
                            height: 28 * Theme.uiScale
                            radius: 14 * Theme.uiScale
                            color: Theme.surface
                            border.color: Theme.outline
                            border.width: 1 * Theme.uiScale
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
                spacing: 8 * Theme.uiScale
                Layout.fillWidth: true
                Layout.topMargin: 4 * Theme.uiScale

                RowLayout {
                    spacing: 8 * Theme.uiScale
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4 * Theme.uiScale
                        Layout.fillWidth: true

                        Text {
                            text: "Show Dock"
                            font.pixelSize: 13 * Theme.uiScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Display a dock at the bottom of the screen for quick access to applications"
                            font.pixelSize: 12 * Theme.uiScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                    }

                    Rectangle {
                        id: dockSwitch

                        width: 52 * Theme.uiScale
                        height: 32 * Theme.uiScale
                        radius: 16 * Theme.uiScale
                        color: Settings.settings.showDock ? Theme.accentPrimary : Theme.surfaceVariant
                        border.color: Settings.settings.showDock ? Theme.accentPrimary : Theme.outline
                        border.width: 2 * Theme.uiScale

                        Rectangle {
                            id: dockThumb

                            width: 28 * Theme.uiScale
                            height: 28 * Theme.uiScale
                            radius: 14 * Theme.uiScale
                            color: Theme.surface
                            border.color: Theme.outline
                            border.width: 1 * Theme.uiScale
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
                spacing: 8 * Theme.uiScale
                Layout.fillWidth: true
                Layout.topMargin: 4 * Theme.uiScale

                RowLayout {
                    spacing: 8 * Theme.uiScale
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 4 * Theme.uiScale
                        Layout.fillWidth: true

                        Text {
                            text: "Dim Desktop"
                            font.pixelSize: 13 * Theme.uiScale
                            font.bold: true
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Dim the desktop when panels or menus are open"
                            font.pixelSize: 12 * Theme.uiScale
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                    }

                    Rectangle {
                        id: dimSwitch

                        width: 52 * Theme.uiScale
                        height: 32 * Theme.uiScale
                        radius: 16 * Theme.uiScale
                        color: Settings.settings.dimPanels ? Theme.accentPrimary : Theme.surfaceVariant
                        border.color: Settings.settings.dimPanels ? Theme.accentPrimary : Theme.outline
                        border.width: 2 * Theme.uiScale

                        Rectangle {
                            id: dimThumb

                            width: 28 * Theme.uiScale
                            height: 28 * Theme.uiScale
                            radius: 14 * Theme.uiScale
                            color: Theme.surface
                            border.color: Theme.outline
                            border.width: 1 * Theme.uiScale
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

    }
}
