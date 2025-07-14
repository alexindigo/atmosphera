import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Qt5Compat.GraphicalEffects
import qs.Settings

Rectangle {
    id: profileSettingsCard
    Layout.fillWidth: true
    Layout.preferredHeight: 340
    color: Theme.surface
    radius: 18
    border.color: "transparent"
    border.width: 0
    Layout.bottomMargin: 16
    property bool showActiveWindowIcon: false
    signal showAWIconChanged(bool showActiveWindowIcon)
    property bool showSystemInfoInBar: true
    signal showSystemInfoChanged(bool showSystemInfoInBar)
    property bool showMediaInBar: false
    signal showMediaChanged(bool showMediaInBar)
    property string visualizerType: Settings.visualizerType
    signal visualizerTypeUpdated(string type)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Profile Image Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "person"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20
                color: Theme.accentPrimary
            }

            Text {
                text: "Profile Image"
                font.pixelSize: 16
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
            }
        }

        // Profile Image Input Row
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: Theme.surfaceVariant
                border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 1

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: Settings.profileImage
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    asynchronous: true
                    cache: false
                    sourceSize.width: 64
                    sourceSize.height: 64
                }
                OpacityMask {
                    anchors.fill: avatarImage
                    source: avatarImage
                    maskSource: Rectangle {
                        width: avatarImage.width
                        height: avatarImage.height
                        radius: avatarImage.width / 2
                        visible: false
                    }
                    visible: Settings.profileImage !== ""
                }

                // Fallback icon
                Text {
                    anchors.centerIn: parent
                    text: "person"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 18
                    color: Theme.accentPrimary
                    visible: Settings.profileImage === ""
                }
            }

            // Text input styled exactly like weather city
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 8
                color: Theme.surfaceVariant
                border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 1

                TextInput {
                    id: profileImageInput
                    anchors.fill: parent
                    anchors.margins: 12
                    text: Settings.profileImage
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    selectByMouse: true
                    activeFocusOnTab: true
                    inputMethodHints: Qt.ImhNone
                    onTextChanged: {
                        Settings.profileImage = text
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            profileImageInput.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // Show Active Window Icon Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Show Active Window Icon"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
            }

            // Custom Material 3 Switch
            Rectangle {
                id: customSwitch
                width: 52
                height: 32
                radius: 16
                color: showActiveWindowIcon ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: showActiveWindowIcon ? Theme.accentPrimary : Theme.outline
                border.width: 2
                
                Rectangle {
                    id: thumb
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: showActiveWindowIcon ? customSwitch.width - width - 2 : 2
                    
                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        showAWIconChanged(!showActiveWindowIcon)
                    }
                }
            }
        }

        // Show System Info In Bar Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Show System Info In Bar"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            // Custom Material 3 Switch
            Rectangle {
                id: customSwitch2
                width: 52
                height: 32
                radius: 16
                color: showSystemInfoInBar ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: showSystemInfoInBar ? Theme.accentPrimary : Theme.outline
                border.width: 2
                
                Rectangle {
                    id: thumb2
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: showSystemInfoInBar ? customSwitch2.width - width - 2 : 2
                    
                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        showSystemInfoChanged(!showSystemInfoInBar)
                    }
                }
            }
        }

        // Show Media In Bar Setting
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Show Media In Bar"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            // Custom Material 3 Switch
            Rectangle {
                id: customSwitch3
                width: 52
                height: 32
                radius: 16
                color: showMediaInBar ? Theme.accentPrimary : Theme.surfaceVariant
                border.color: showMediaInBar ? Theme.accentPrimary : Theme.outline
                border.width: 2
                
                Rectangle {
                    id: thumb3
                    width: 28
                    height: 28
                    radius: 14
                    color: Theme.surface
                    border.color: Theme.outline
                    border.width: 1
                    y: 2
                    x: showMediaInBar ? customSwitch3.width - width - 2 : 2
                    
                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        showMediaChanged(!showMediaInBar)
                    }
                }
            }
        }

        // Visualizer Type Selection
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Visualizer Type"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            // Dropdown for visualizer type
            Rectangle {
                width: 120
                height: 36
                radius: 8
                color: Theme.surfaceVariant
                border.color: Theme.outline
                border.width: 1

                Text {
                    id: visualizerTypeText
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: visualizerType === "fire" ? "Fire" : 
                          visualizerType === "diamond" ? "Diamond" : 
                          visualizerType === "radial" ? "Radial" : "Radial"
                    font.pixelSize: 13
                    color: Theme.textPrimary
                }

                Text {
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    color: Theme.textPrimary
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        visualizerTypeMenu.open()
                    }
                }

                Menu {
                    id: visualizerTypeMenu
                    width: 120
                    y: parent.height

                    MenuItem {
                        text: "Fire"
                        onTriggered: {
                            visualizerTypeUpdated("fire")
                        }
                    }
                    MenuItem {
                        text: "Diamond"
                        onTriggered: {
                            visualizerTypeUpdated("diamond")
                        }
                    }
                    MenuItem {
                        text: "Radial"
                        onTriggered: {
                            visualizerTypeUpdated("radial")
                        }
                    }
                }
            }
        }

        // Video Path Input Row
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: "Video Path"
                font.pixelSize: 13
                font.bold: true
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 8
                color: Theme.surfaceVariant
                border.color: videoPathInput.activeFocus ? Theme.accentPrimary : Theme.outline
                border.width: 1

                TextInput {
                    id: videoPathInput
                    anchors.fill: parent
                    anchors.margins: 12
                    text: Settings.videoPath !== undefined ? Settings.videoPath : ""
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true
                    activeFocusOnTab: true
                    inputMethodHints: Qt.ImhUrlCharactersOnly
                    onTextChanged: {
                        Settings.videoPath = text
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: videoPathInput.forceActiveFocus()
                    }
                }
            }
        }
    }
} 
