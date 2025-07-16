import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs.Settings

Rectangle {
    id: settingsModal
    anchors.centerIn: parent
    color: Theme.backgroundPrimary
    radius: 20
    visible: false
    z: 100
    

    // Local properties for editing (not saved until apply)
    property string tempWeatherCity: Settings.weatherCity
    property bool tempUseFahrenheit: false
    property string tempProfileImage: Settings.profileImage
    property string tempWallpaperFolder: Settings.wallpaperFolder

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Text {
                text: "settings"
                font.family: "Material Symbols Outlined"
                font.pixelSize: Theme.fontSizeHeader
                color: Theme.accentPrimary
            }

            Text {
                text: "Settings"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                border.color: Theme.accentPrimary
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "close"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: Theme.fontSizeBody
                    color: closeButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                }

                MouseArea {
                    id: closeButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: settingsModal.closeSettings()
                }
            }
        }

        // Weather Settings Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            color: Theme.surface
            radius: 18

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                // Weather Settings Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "wb_sunny"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.accentPrimary
                    }

                    Text {
                        text: "Weather Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                }

                // Weather City Setting
                ColumnLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    Text {
                        text: "City"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 8
                        color: Theme.surfaceVariant
                        border.color: cityInput.activeFocus ? Theme.accentPrimary : Theme.outline
                        border.width: 1

                        TextInput {
                            id: cityInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            text: tempWeatherCity
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: true
                            selectByMouse: true
                            activeFocusOnTab: true
                            inputMethodHints: Qt.ImhNone

                            onTextChanged: {
                                tempWeatherCity = text
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    cityInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // Temperature Unit Setting
                RowLayout {
                    spacing: 12
                    Layout.fillWidth: true

                    Text {
                        text: "Temperature Unit"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
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
                        color: Theme.accentPrimary
                        border.color: Theme.accentPrimary
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
                            x: tempUseFahrenheit ? customSwitch.width - width - 2 : 2
                            
                            Text {
                                anchors.centerIn: parent
                                text: tempUseFahrenheit ? "°F" : "°C"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                                color: Theme.textPrimary
                            }
                            
                            Behavior on x {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                tempUseFahrenheit = !tempUseFahrenheit
                            }
                        }
                    }
                }
            }
        }

        // Profile Image Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            color: Theme.surface
            radius: 18
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 0
            border.color: "transparent"
            border.width: 0
            Layout.bottomMargin: 16

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
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.accentPrimary
                    }

                                            Text {
                            text: "Profile Image"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
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
                            source: tempProfileImage
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            asynchronous: true
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
                            visible: tempProfileImage !== ""
                        }

                        // Fallback icon
                        Text {
                            anchors.centerIn: parent
                            text: "person"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.accentPrimary
                            visible: tempProfileImage === ""
                        }
                    }

                    // Text input styled exactly like weather city
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 8
                        color: Theme.surfaceVariant
                        border.color: profileImageInput.activeFocus ? Theme.accentPrimary : Theme.outline
                        border.width: 1

                        TextInput {
                            id: profileImageInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            text: tempProfileImage
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            focus: true
                            selectByMouse: true
                            activeFocusOnTab: true
                            inputMethodHints: Qt.ImhNone
                            onTextChanged: {
                                tempProfileImage = text
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
            }
        }

        // Wallpaper Folder Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            color: Theme.surface
            radius: 18

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: "image"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.accentPrimary
                    }
                    Text {
                        text: "Wallpaper Folder"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                }

                // Folder Path Input
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 8
                    color: Theme.surfaceVariant
                    border.color: wallpaperFolderInput.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1

                    TextInput {
                        id: wallpaperFolderInput
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        text: tempWallpaperFolder
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                        onTextChanged: tempWallpaperFolder = text
                        MouseArea {
                            anchors.fill: parent
                            onClicked: wallpaperFolderInput.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // Spacer to push content to top
        Item {
            Layout.fillHeight: true
        }

        // Apply Button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 12
            color: applyButtonArea.containsMouse ? Theme.accentPrimary : Theme.accentPrimary
            border.color: "transparent"
            border.width: 0
            opacity: 1.0

            Text {
                anchors.centerIn: parent
                text: "Apply Changes"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: applyButtonArea.containsMouse ? Theme.onAccent : Theme.onAccent
            }

            MouseArea {
                id: applyButtonArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    // Apply the changes
                    Settings.weatherCity = tempWeatherCity
                    Settings.useFahrenheit = tempUseFahrenheit
                    Settings.profileImage = tempProfileImage
                    Settings.wallpaperFolder = tempWallpaperFolder
                    // Force save settings
                    Settings.saveSettings()
                    // Refresh weather if available
                    if (typeof weather !== 'undefined' && weather) {
                        weather.fetchCityWeather()
                    }
                    // Close the modal
                    settingsModal.closeSettings()
                }
            }
        }
    }

    // Function to open the modal and initialize temp values
    function openSettings() {
        tempWeatherCity = Settings.weatherCity
        tempUseFahrenheit = Settings.useFahrenheit
        tempProfileImage = Settings.profileImage
        tempWallpaperFolder = Settings.wallpaperFolder
        visible = true
        // Force focus on the text input after a short delay
        focusTimer.start()
    }

    // Function to close the modal and release focus
    function closeSettings() {
        visible = false
        cityInput.focus = false
        profileImageInput.focus = false
        wallpaperFolderInput.focus = false
    }

    Timer {
        id: focusTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (visible) {
                cityInput.forceActiveFocus()
                // Optionally, also focus profileImageInput if you want both to get focus:
                // profileImageInput.forceActiveFocus()
            }
        }
    }

    // Release focus when modal becomes invisible
    onVisibleChanged: {
        if (!visible) {
            cityInput.focus = false
            profileImageInput.focus = false
            wallpaperFolderInput.focus = false
        }
    }
} 