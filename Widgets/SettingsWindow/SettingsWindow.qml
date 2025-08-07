import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Settings
import qs.Widgets.SettingsWindow.Tabs
import qs.Widgets.SettingsWindow.Tabs.Components

PanelWithOverlay {
    id: panelMain

    property int activeTabIndex: 0

    // Function to show wallpaper selector
    function showWallpaperSelector() {
        if (wallpaperSelector)
            wallpaperSelector.show();

    }

    // Function to show settings window
    function showSettings() {
        show();
    }

    // Function to load component for a specific tab
    function loadComponentForTab(tabIndex) {
        const componentMap = {
            "0": generalSettings,
            "1": barSettings,
            "2": timeWeatherSettings,
            "3": recordingSettings,
            "4": networkSettings,
            "5": displaySettings,
            "6": wallpaperSettings,
            "7": miscSettings,
            "8": aboutSettings
        };
        const tabNames = ["General", "Bar", "Time & Weather", "Screen Recorder", "Network", "Display", "Wallpaper", "Misc", "About"];
        if (componentMap[tabIndex]) {
            settingsLoader.sourceComponent = componentMap[tabIndex];
            if (tabName)
                tabName.text = tabNames[tabIndex];

        }
    }

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    // Handle activeTabIndex changes
    onActiveTabIndexChanged: {
        if (activeTabIndex >= 0 && activeTabIndex <= 8)
            loadComponentForTab(activeTabIndex);

    }
    // Add safety checks for component loading
    Component.onCompleted: {
        // Ensure we start with a valid tab
        if (activeTabIndex < 0 || activeTabIndex > 8)
            activeTabIndex = 0;

    }
    // Cleanup when window is hidden
    onVisibleChanged: {
        if (!visible) {
            // Reset to default tab when hiding to prevent state issues
            activeTabIndex = 0;
            if (tabName)
                tabName.text = "General";

        }
    }

    Component {
        id: generalSettings

        General {
        }

    }

    Component {
        id: barSettings

        Bar {
        }

    }

    Component {
        id: timeWeatherSettings

        TimeWeather {
        }

    }

    Component {
        id: recordingSettings

        Recording {
        }

    }

    Component {
        id: networkSettings

        Network {
        }

    }

    Component {
        id: miscSettings

        Misc {
        }

    }

    Component {
        id: aboutSettings

        About {
        }

    }

    Component {
        id: displaySettings

        Display {
        }

    }

    Component {
        id: wallpaperSettings

        Wallpaper {
        }

    }

    Rectangle {
        id: settingsWindowRect

        implicitWidth: Quickshell.screens.length > 0 ? Math.min(Quickshell.screens[0].width * 2 / 3, 1200) * Theme.uiScale : 600 * Theme.uiScale
        implicitHeight: Quickshell.screens.length > 0 ? Math.min(Quickshell.screens[0].height * 2 / 3, 800) * Theme.uiScale : 400 * Theme.uiScale
        visible: parent.visible
        color: "transparent"
        // Center the settings window on screen
        anchors.centerIn: parent

        // Prevent closing when clicking in the panel bg
        MouseArea {
            anchors.fill: parent
        }

        // Background rectangle
        Rectangle {
            id: background

            color: Theme.backgroundPrimary
            anchors.fill: parent
            radius: 20 * Theme.uiScale
            border.color: Theme.outline
            border.width: 1 * Theme.uiScale

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
            clip: true

            color: Theme.backgroundPrimary
            topRightRadius: 20 * Theme.uiScale
            bottomRightRadius: 20 * Theme.uiScale

            anchors {
                left: tabs.right
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                margins: 12
            }

                Rectangle {
                    id: headerArea

                    height: 48 * Theme.uiScale
                    color: "transparent"

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 16
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12 * Theme.uiScale

                        Text {
                            id: tabName

                            text: wallpaperSelector.visible ? "Select Wallpaper" : (activeTabIndex === 0 ? "General" : activeTabIndex === 1 ? "Bar" : activeTabIndex === 2 ? "Time & Weather" : activeTabIndex === 3 ? "Screen Recorder" : activeTabIndex === 4 ? "Network" : activeTabIndex === 5 ? "Display" : activeTabIndex === 6 ? "Wallpaper" : activeTabIndex === 7 ? "Misc" : activeTabIndex === 8 ? "About" : "General")
                            font.pixelSize: 18 * Theme.uiScale
                            font.bold: true
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }

                        // Wallpaper Selection Button (only visible on Wallpaper tab)
                        Rectangle {
                            width: 160 * Theme.uiScale
                            height: 32 * Theme.uiScale
                            radius: 16 * Theme.uiScale
                            color: wallpaperButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                            border.color: Theme.accentPrimary
                            border.width: 1 * Theme.uiScale
                            visible: activeTabIndex === 6 // Wallpaper tab index

                            Row {
                                anchors.centerIn: parent
                                spacing: 6 * Theme.uiScale

                                Text {
                                    text: "image"
                                    font.family: wallpaperButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                                    font.pixelSize: 16 * Theme.uiScale
                                    color: wallpaperButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Select Wallpaper"
                                    font.pixelSize: 13 * Theme.uiScale
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
                            width: 32 * Theme.uiScale
                            height: 32 * Theme.uiScale
                            radius: 16 * Theme.uiScale
                            color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                            border.color: Theme.accentPrimary
                            border.width: 1 * Theme.uiScale

                            Text {
                                anchors.centerIn: parent
                                text: "close"
                                font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                                font.pixelSize: 18 * Theme.uiScale
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
                    height: 1 * Theme.uiScale
                    color: Theme.outline
                    opacity: 0.3

                    anchors {
                        top: headerArea.bottom
                        left: parent.left
                        right: parent.right
                        margins: 16
                    }

                }

                ColumnLayout {
                    id: settingsContainer

                    anchors {
                        top: headerArea.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        topMargin: 32
                    }

                    // Simplified single loader approach
                    Loader {
                        id: settingsLoader

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        sourceComponent: generalSettings
                        active: true
                    }

                    // Wallpaper Selector Component
                    WallpaperSelector {
                        id: wallpaperSelector
                    }

                }

            }

            Rectangle {
                id: tabs

                color: Theme.surface
                width: parent.width * 0.25
                height: settingsWindowRect.height
                topLeftRadius: 20 * Theme.uiScale
                bottomLeftRadius: 20 * Theme.uiScale
                border.color: Theme.outline
                border.width: 1 * Theme.uiScale

                Column {
                    width: parent.width
                    spacing: 0 * Theme.uiScale
                    topPadding: 8 * Theme.uiScale
                    bottomPadding: 8 * Theme.uiScale

                    Repeater {
                        id: repeater

                        model: [{
                            "icon": "tune",
                            "text": "General"
                        }, {
                            "icon": "space_dashboard",
                            "text": "Bar"
                        }, {
                            "icon": "schedule",
                            "text": "Time & Weather"
                        }, {
                            "icon": "photo_camera",
                            "text": "Screen Recorder"
                        }, {
                            "icon": "wifi",
                            "text": "Network"
                        }, {
                            "icon": "monitor",
                            "text": "Display"
                        }, {
                            "icon": "wallpaper",
                            "text": "Wallpaper"
                        }, {
                            "icon": "settings_suggest",
                            "text": "Misc"
                        }, {
                            "icon": "info",
                            "text": "About"
                        }]

                        delegate: Rectangle {
                            width: tabs.width
                            height: 48 * Theme.uiScale
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8 * Theme.uiScale

                                Rectangle {
                                    id: activeIndicator

                                    Layout.leftMargin: 8 * Theme.uiScale
                                    Layout.preferredWidth: 3 * Theme.uiScale
                                    Layout.preferredHeight: 24 * Theme.uiScale
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 2 * Theme.uiScale
                                    color: Theme.accentPrimary
                                    opacity: index === activeTabIndex ? 1 : 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 200
                                        }

                                    }

                                }

                                Label {
                                    id: icon

                                    text: modelData.icon
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 24 * Theme.uiScale
                                    color: index === activeTabIndex ? Theme.accentPrimary : Theme.textPrimary
                                    opacity: index === activeTabIndex ? 1 : 0.8
                                    Layout.leftMargin: 20 * Theme.uiScale
                                    Layout.preferredWidth: 24 * Theme.uiScale
                                    Layout.preferredHeight: 24 * Theme.uiScale
                                    Layout.alignment: Qt.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.variableAxes: { "wght": (Font.Normal + Font.Bold) / 2.0 }
                                }

                                Label {
                                    id: label

                                    text: modelData.text
                                    font.pixelSize: 16 * Theme.uiScale
                                    color: index === activeTabIndex ? Theme.accentPrimary : (tabMouseArea.containsMouse ? Theme.accentPrimary : Theme.textSecondary)
                                    font.weight: index === activeTabIndex ? Font.DemiBold : (tabMouseArea.containsMouse ? Font.DemiBold : Font.Normal)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24 * Theme.uiScale
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    Layout.leftMargin: 4 * Theme.uiScale
                                    Layout.rightMargin: 16 * Theme.uiScale
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
                                height: 1 * Theme.uiScale
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
