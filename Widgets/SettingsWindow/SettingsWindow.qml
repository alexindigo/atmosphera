import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.Settings
import qs.Widgets.SettingsWindow.Tabs
import qs.Widgets.SettingsWindow.Tabs.Components
import qs.Components

PanelWithOverlay {
    id: panelMain
    
    property int activeTabIndex: 0

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Function to show wallpaper selector
    function showWallpaperSelector() {
        if (wallpaperSelector) {
            wallpaperSelector.show();
        }
    }

    // Function to show settings window
    function showSettings() {
        show();
    }
    

    


        // Handle activeTabIndex changes
    onActiveTabIndexChanged: {
        if (activeTabIndex >= 0 && activeTabIndex <= 8) {
            loadComponentForTab(activeTabIndex);
        }
    }

    // Function to load component for a specific tab
    function loadComponentForTab(tabIndex) {
        const componentMap = {
            0: generalSettings,
            1: barSettings,
            2: timeWeatherSettings,
            3: recordingSettings,
            4: networkSettings,
            5: displaySettings,
            6: wallpaperSettings,
            7: miscSettings,
            8: aboutSettings
        };
        
        const tabNames = [
            "General",
            "Bar",
            "Time & Weather", 
            "Screen Recorder",
            "Network",
            "Display",
            "Wallpaper",
            "Misc",
            "About"
        ];
        
        if (componentMap[tabIndex]) {
            settingsLoader.sourceComponent = componentMap[tabIndex];
            if (tabName) {
                tabName.text = tabNames[tabIndex];
            }
            

        }
    }

    // Add safety checks for component loading
    Component.onCompleted: {
        // Ensure we start with a valid tab
        if (activeTabIndex < 0 || activeTabIndex > 8) {
            activeTabIndex = 0;
        }
    }

    // Cleanup when window is hidden
    onVisibleChanged: {
        if (!visible) {
            // Reset to default tab when hiding to prevent state issues
            activeTabIndex = 0;
            if (tabName) {
                tabName.text = "General";
            }
        }
    }

    Component {
        id: generalSettings
        General {}
    }

    Component {
        id: barSettings
        Bar {}
    }

    Component {
        id: timeWeatherSettings
        TimeWeather {}
    }

    Component {
        id: recordingSettings
        Recording {}
    }

    Component {
        id: networkSettings
        Network {}
    }

    Component {
        id: miscSettings
        Misc {}
    }

    Component {
        id: aboutSettings
        About {}
    }

    Component {
        id: displaySettings
        Display {}
    }

    Component {
        id: wallpaperSettings
        Wallpaper {}
    }

    Rectangle {
        id: settingsWindowRect
        implicitWidth: Quickshell.screens.length > 0 ? Quickshell.screens[0].width / 2 : 600
        implicitHeight: Quickshell.screens.length > 0 ? Quickshell.screens[0].height / 2 : 400
        visible: parent.visible
        color: "transparent"
        
        // Center the settings window on screen
        anchors.centerIn: parent

        Rectangle {
            id: background
            color: Theme.backgroundPrimary
            anchors.fill: parent
            radius: 20
            border.color: Theme.outline
            border.width: 1

            MultiEffect {
                source: background
                anchors.fill: background
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowOpacity: 0.3
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 2
                shadowBlur: 12
            }
        }

        Rectangle {
            id: settings
            color: Theme.backgroundPrimary
            anchors {
                left: tabs.right
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                margins: 12
            }
            topRightRadius: 20
            bottomRightRadius: 20

        Rectangle {
            id: headerArea
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            height: 48
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                spacing: 12

                Text {
                    id: tabName
                    text: wallpaperSelector.visible ? "Select Wallpaper" : (activeTabIndex === 0 ? "General" : 
                         activeTabIndex === 1 ? "Bar" : 
                         activeTabIndex === 2 ? "Time & Weather" : 
                         activeTabIndex === 3 ? "Screen Recorder" : 
                         activeTabIndex === 4 ? "Network" : 
                         activeTabIndex === 5 ? "Display" : 
                         activeTabIndex === 6 ? "Wallpaper" : 
                         activeTabIndex === 7 ? "Misc" : 
                         activeTabIndex === 8 ? "About" : "General")
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.fillWidth: true
                }

                // Wallpaper Selection Button (only visible on Wallpaper tab)
                Rectangle {
                    width: 160
                    height: 32
                    radius: 16
                    color: wallpaperButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                    border.color: Theme.accentPrimary
                    border.width: 1
                    visible: activeTabIndex === 6 // Wallpaper tab index

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "image"
                            font.family: wallpaperButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: wallpaperButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Select Wallpaper"
                            font.pixelSize: 13
                            font.bold: true
                            color: wallpaperButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: wallpaperButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Show the wallpaper selector
                            wallpaperSelector.show();
                        }
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                    border.color: Theme.accentPrimary
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                        font.pixelSize: 18
                        color: closeButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                    }

                    MouseArea {
                        id: closeButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panelMain.dismiss()
                    }
                }
            }
        }

        Rectangle {
            anchors {
                top: headerArea.bottom
                left: parent.left
                right: parent.right
                margins: 16
            }
            height: 1
            color: Theme.outline
            opacity: 0.3
        }

        Item {
            id: settingsContainer
            anchors {
                top: headerArea.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 16
                topMargin: 32
            }

            // Simplified single loader approach
            Loader {
                id: settingsLoader
                anchors.fill: parent
                sourceComponent: generalSettings
            }

            // Wallpaper Selector Component
            WallpaperSelector {
                id: wallpaperSelector
                anchors.fill: parent
            }
        }
    }

        Rectangle {
            id: tabs
            color: Theme.surface
            width: Quickshell.screens.length > 0 ? Quickshell.screens[0].width / 9 : 100
            height: settingsWindowRect.height
            topLeftRadius: 20
            bottomLeftRadius: 20
            border.color: Theme.outline
            border.width: 1

        Column {
            width: parent.width
            spacing: 0
            topPadding: 8
            bottomPadding: 8

            Repeater {
                id: repeater
                model: [
                    { icon: "tune", text: "General" },
                    { icon: "space_dashboard", text: "Bar" },
                    { icon: "schedule", text: "Time & Weather" },
                    { icon: "photo_camera", text: "Screen Recorder" },
                    { icon: "wifi", text: "Network" },
                    { icon: "monitor", text: "Display" },
                    { icon: "wallpaper", text: "Wallpaper" },
                    { icon: "settings_suggest", text: "Misc" },
                    { icon: "info", text: "About" }
                ]

                delegate: Rectangle {
                    width: tabs.width
                    height: 48
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        Rectangle {
                            id: activeIndicator
                            Layout.leftMargin: 8
                            Layout.preferredWidth: 3
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            radius: 2
                            color: Theme.accentPrimary
                            opacity: index === activeTabIndex ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        Label {
                            id: icon
                            text: modelData.icon
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24
                            color: index === activeTabIndex ? Theme.accentPrimary : Theme.textPrimary
                            opacity: index === activeTabIndex ? 1 : 0.8
                            Layout.leftMargin: 20
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        Label {
                            id: label
                            text: modelData.text
                            font.pixelSize: 16
                            color: index === activeTabIndex ? Theme.accentPrimary : 
                                   (tabMouseArea.containsMouse ? Theme.accentPrimary : Theme.textSecondary)
                            font.weight: index === activeTabIndex ? Font.DemiBold : 
                                       (tabMouseArea.containsMouse ? Font.DemiBold : Font.Normal)
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                            Layout.leftMargin: 4
                            Layout.rightMargin: 16
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: tabMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            activeTabIndex = index;
                            loadComponentForTab(index);
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outline
                        opacity: 0.6
                        visible: index < (repeater.count - 1)
                        anchors.bottom: parent.bottom
                    }
                }
            }
        }
    }
    }
}