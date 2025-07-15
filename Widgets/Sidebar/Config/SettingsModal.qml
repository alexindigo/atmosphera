import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Quickshell
import Quickshell.Wayland
import qs.Settings
import qs.Services
import qs.Components

PanelWindow {
    id: settingsModal
    implicitWidth: 480
    implicitHeight: 800
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.right: true
    margins.right: 0
    margins.top: -24
    //z: 100
    //border.color: Theme.outline
    //border.width: 1
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Local properties for editing (not saved until apply)
    property string tempWeatherCity: (Settings.weatherCity !== undefined && Settings.weatherCity !== null) ? Settings.weatherCity : ""
    property bool tempUseFahrenheit: Settings.useFahrenheit
    property string tempProfileImage: (Settings.profileImage !== undefined && Settings.profileImage !== null) ? Settings.profileImage : ""
    property string tempWallpaperFolder: (Settings.wallpaperFolder !== undefined && Settings.wallpaperFolder !== null) ? Settings.wallpaperFolder : ""
    property bool tempShowActiveWindowIcon: Settings.showActiveWindowIcon
    property bool tempUseSWWW: Settings.useSWWW
    property bool tempRandomWallpaper: Settings.randomWallpaper
    property bool tempUseWallpaperTheme: Settings.useWallpaperTheme
    property int tempWallpaperInterval: Settings.wallpaperInterval
    property string tempWallpaperResize: Settings.wallpaperResize
    property int tempTransitionFps: Settings.transitionFps
    property string tempTransitionType: Settings.transitionType
    property real tempTransitionDuration: Settings.transitionDuration
    property bool tempShowSystemInfoInBar: Settings.showSystemInfoInBar
    property bool tempShowMediaInBar: Settings.showMediaInBar
    property string tempVisualizerType: Settings.visualizerType

    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundPrimary
        radius: 24
        //border.color: Theme.outline
        //border.width: 1
        z: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 24

            // Header
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    Text {
                        text: "settings"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 32
                        color: Theme.accentPrimary
                    }
                    Text {
                        text: "Settings"
                        font.pixelSize: 26
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
                            font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                            font.pixelSize: 20
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
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.outline
                    opacity: 0.12
                }
            }

            // Tabs bar (moved here)
            Tabs {
                id: settingsTabs
                Layout.fillWidth: true
                tabsModel: [
                    { icon: "cloud", label: "Weather" },
                    { icon: "settings", label: "System" },
                    { icon: "wallpaper", label: "Wallpaper" }
                ]
            }

            // Scrollable settings area
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 520
                color: "transparent"
                border.width: 0
                radius: 20

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: tabContentLoader.item ? tabContentLoader.item.implicitHeight : 0
                    clip: true

                    Loader {
                        id: tabContentLoader
                        anchors.top: parent.top
                        width: parent.width
                        sourceComponent: settingsTabs.currentIndex === 0 ? weatherTab : settingsTabs.currentIndex === 1 ? systemTab : wallpaperTab
                    }
                }

                Component {
                    id: weatherTab
                    ColumnLayout {
                        anchors.fill: parent
                        WeatherSettings {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            anchors.margins: 16
                            weatherCity: (typeof tempWeatherCity !== 'undefined' && tempWeatherCity !== null) ? tempWeatherCity : ""
                            useFahrenheit: tempUseFahrenheit
                            onCityChanged: function (city) {
                                tempWeatherCity = city;
                            }
                            onTemperatureUnitChanged: function (useFahrenheit) {
                                tempUseFahrenheit = useFahrenheit;
                            }
                        }
                    }
                }
                Component {
                    id: systemTab
                    ColumnLayout {
                        anchors.fill: parent
                        ProfileSettings {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            anchors.margins: 16
                            showActiveWindowIcon: tempShowActiveWindowIcon
                            onShowAWIconChanged: function (showActiveWindowIcon) {
                                tempShowActiveWindowIcon = showActiveWindowIcon;
                            }
                            showSystemInfoInBar: tempShowSystemInfoInBar
                            onShowSystemInfoChanged: function (showSystemInfoInBar) {
                                tempShowSystemInfoInBar = showSystemInfoInBar;
                            }
                            showMediaInBar: tempShowMediaInBar
                            onShowMediaChanged: function (showMediaInBar) {
                                tempShowMediaInBar = showMediaInBar;
                            }
                            visualizerType: tempVisualizerType
                            onVisualizerTypeUpdated: function (type) {
                                tempVisualizerType = type;
                            }
                        }
                    }
                }
                Component {
                    id: wallpaperTab
                    ColumnLayout {
                        anchors.fill: parent
                        WallpaperSettings {
                            id: wallpaperSettings
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            anchors.margins: 16
                            wallpaperFolder: (typeof tempWallpaperFolder !== 'undefined' && tempWallpaperFolder !== null) ? tempWallpaperFolder : ""
                            useSWWW: tempUseSWWW
                            randomWallpaper: tempRandomWallpaper
                            useWallpaperTheme: tempUseWallpaperTheme
                            wallpaperInterval: tempWallpaperInterval
                            wallpaperResize: tempWallpaperResize
                            transitionFps: tempTransitionFps
                            transitionType: tempTransitionType
                            transitionDuration: tempTransitionDuration
                            onWallpaperFolderEdited: function (folder) {
                                tempWallpaperFolder = folder;
                            }
                            onUseSWWWChangedUpdated: function(useSWWW) {
                                tempUseSWWW = useSWWW;
                            }
                            onRandomWallpaperChangedUpdated: function(randomWallpaper) {
                                tempRandomWallpaper = randomWallpaper;
                            }
                            onUseWallpaperThemeChangedUpdated: function(useWallpaperTheme) {
                                tempUseWallpaperTheme = useWallpaperTheme;
                            }
                            onWallpaperIntervalChangedUpdated: function(wallpaperInterval) {
                                tempWallpaperInterval = wallpaperInterval;
                            }
                            onWallpaperResizeChangedUpdated: function(resize) {
                                tempWallpaperResize = resize;
                            }
                            onTransitionFpsChangedUpdated: function(fps) {
                                tempTransitionFps = fps;
                            }
                            onTransitionTypeChangedUpdated: function(type) {
                                tempTransitionType = type;
                            }
                            onTransitionDurationChangedUpdated: function(duration) {
                                tempTransitionDuration = duration;
                            }
                        }
                    }
                }
            }

            // Apply Button
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 16
                color: applyButtonArea.containsMouse ? Theme.accentPrimary : Theme.accentPrimary
                border.color: "transparent"
                border.width: 0
                opacity: 1.0
                Text {
                    anchors.centerIn: parent
                    text: "Apply Changes"
                    font.pixelSize: 17
                    font.bold: true
                    color: applyButtonArea.containsMouse ? Theme.onAccent : Theme.onAccent
                }
                MouseArea {
                    id: applyButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Settings.weatherCity = (typeof tempWeatherCity !== 'undefined' && tempWeatherCity !== null) ? tempWeatherCity : "";
                        Settings.useFahrenheit = tempUseFahrenheit;
                        Settings.profileImage = (typeof tempProfileImage !== 'undefined' && tempProfileImage !== null) ? tempProfileImage : "";
                        Settings.wallpaperFolder = (typeof tempWallpaperFolder !== 'undefined' && tempWallpaperFolder !== null) ? tempWallpaperFolder : "";
                        Settings.showActiveWindowIcon = tempShowActiveWindowIcon;
                        Settings.useSWWW = tempUseSWWW;
                        Settings.randomWallpaper = tempRandomWallpaper;
                        Settings.useWallpaperTheme = tempUseWallpaperTheme;
                        Settings.wallpaperInterval = tempWallpaperInterval;
                        Settings.wallpaperResize = tempWallpaperResize;
                        Settings.transitionFps = tempTransitionFps;
                        Settings.transitionType = tempTransitionType;
                        Settings.transitionDuration = tempTransitionDuration;
                        Settings.showSystemInfoInBar = tempShowSystemInfoInBar;
                        Settings.showMediaInBar = tempShowMediaInBar;
                        Settings.visualizerType = tempVisualizerType;
                        Settings.saveSettings();
                        if (typeof weather !== 'undefined' && weather) {
                            weather.fetchCityWeather();
                        }
                        settingsModal.closeSettings();
                    }
                }
            }
        }
    }

    // Function to open the modal and initialize temp values
    function openSettings() {
        tempWeatherCity = (Settings.weatherCity !== undefined && Settings.weatherCity !== null) ? Settings.weatherCity : "";
        tempUseFahrenheit = Settings.useFahrenheit;
        tempShowActiveWindowIcon = Settings.showActiveWindowIcon;
        tempProfileImage = (Settings.profileImage !== undefined && Settings.profileImage !== null) ? Settings.profileImage : "";
        tempWallpaperFolder = (Settings.wallpaperFolder !== undefined && Settings.wallpaperFolder !== null) ? Settings.wallpaperFolder : "";
        if (tempWallpaperFolder === undefined || tempWallpaperFolder === null)
            tempWallpaperFolder = "";
        
        // Initialize wallpaper settings
        tempUseSWWW = Settings.useSWWW;
        tempRandomWallpaper = Settings.randomWallpaper;
        tempUseWallpaperTheme = Settings.useWallpaperTheme;
        tempWallpaperInterval = Settings.wallpaperInterval;
        tempWallpaperResize = Settings.wallpaperResize;
        tempTransitionFps = Settings.transitionFps;
        tempTransitionType = Settings.transitionType;
        tempTransitionDuration = Settings.transitionDuration;
        tempShowSystemInfoInBar = Settings.showSystemInfoInBar;
        tempShowMediaInBar = Settings.showMediaInBar;
        tempVisualizerType = Settings.visualizerType;
        
        visible = true;
        // Force focus on the text input after a short delay
        focusTimer.start();
    }

    // Function to close the modal and release focus
    function closeSettings() {
        visible = false;
    }

    Timer {
        id: focusTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (visible)
            // Focus will be handled by the individual components
            {}
        }
    }

    // Release focus when modal becomes invisible
    onVisibleChanged: {
        if (!visible)
        // Focus will be handled by the individual components
        {}
    }
}

