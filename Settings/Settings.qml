pragma Singleton
import QtQuick
import QtCore
import Quickshell
import qs.Services

QtObject {

    Component.onCompleted: {
        Qt.application.name = "quickshell"
        Qt.application.organization = "quickshell"
        Qt.application.domain = "quickshell.app"
        loadSettings()
    }
    property string weatherCity: "Dinslaken"
    property string profileImage: "/home/" + Quickshell.env("USER") + "/.face"
    property bool useFahrenheit: false
    property string wallpaperFolder: "/usr/share/wallpapers"
    property string currentWallpaper: ""
    property string videoPath: "~/Videos/"
    property bool showActiveWindowIcon: false
    property bool useSWWW: false
    property bool randomWallpaper: false
    property bool useWallpaperTheme: false
    property bool showSystemInfoInBar: true
    property bool showMediaInBar: false
    property int wallpaperInterval: 300
    property string wallpaperResize: "crop"
    property int transitionFps: 60
    property string transitionType: "random"
    property real transitionDuration: 1.1
    property string visualizerType: "radial" // Options: "fire", "diamond", "radial"

    // Settings persistence
    property var settings: Settings {
        category: "quickshell"
    }

    function loadSettings() {
        weatherCity = settings.value("weatherCity", weatherCity)
        profileImage = settings.value("profileImage", profileImage)
        let tempUnit = settings.value("weatherTempUnit", "celsius")
        useFahrenheit = (tempUnit === "fahrenheit")
        wallpaperFolder = settings.value("wallpaperFolder", wallpaperFolder)
        currentWallpaper = settings.value("currentWallpaper", currentWallpaper)
        videoPath = settings.value("videoPath", videoPath)
        let showActiveWindowIconFlag = settings.value("showActiveWindowIconFlag", "false")
        showActiveWindowIcon = showActiveWindowIconFlag === "true"
        let showSystemInfoInBarFlag = settings.value("showSystemInfoInBarFlag", "true")
        showSystemInfoInBar = showSystemInfoInBarFlag === "true"
        let showMediaInBarFlag = settings.value("showMediaInBarFlag", "true")
        showMediaInBar = showMediaInBarFlag === "true"
        let useSWWWFlag = settings.value("useSWWWFlag", "false")
        useSWWW = useSWWWFlag === "true"
        let randomWallpaperFlag = settings.value("randomWallpaperFlag", "false")
        randomWallpaper = randomWallpaperFlag === "true"
        let useWallpaperThemeFlag = settings.value("useWallpaperThemeFlag", "false")
        useWallpaperTheme = useWallpaperThemeFlag === "true"
        wallpaperInterval = settings.value("wallpaperInterval", wallpaperInterval)
        wallpaperResize = settings.value("wallpaperResize", wallpaperResize)
        transitionFps = settings.value("transitionFps", transitionFps)
        transitionType = settings.value("transitionType", transitionType)
        transitionDuration = settings.value("transitionDuration", transitionDuration)
        visualizerType = settings.value("visualizerType", visualizerType)
        
        WallpaperManager.setCurrentWallpaper(currentWallpaper, true);
    }

    function saveSettings() {
        settings.setValue("weatherCity", weatherCity)
        settings.setValue("profileImage", profileImage)
        settings.setValue("weatherTempUnit", useFahrenheit ? "fahrenheit" : "celsius")
        settings.setValue("wallpaperFolder", wallpaperFolder)
        settings.setValue("currentWallpaper", currentWallpaper)
        settings.setValue("videoPath", videoPath)
        settings.setValue("showActiveWindowIconFlag", showActiveWindowIcon ? "true" : "false")
        settings.setValue("showSystemInfoInBarFlag", showSystemInfoInBar ? "true" : "false")
        settings.setValue("showMediaInBarFlag", showMediaInBar ? "true" : "false")
        settings.setValue("useSWWWFlag", useSWWW ? "true" : "false")
        settings.setValue("randomWallpaperFlag", randomWallpaper ? "true" : "false")
        settings.setValue("useWallpaperThemeFlag", useWallpaperTheme ? "true" : "false")
        settings.setValue("wallpaperInterval", wallpaperInterval)
        settings.setValue("wallpaperResize", wallpaperResize)
        settings.setValue("transitionFps", transitionFps)
        settings.setValue("transitionType", transitionType)
        settings.setValue("transitionDuration", transitionDuration)
        settings.setValue("visualizerType", visualizerType)
        settings.sync()
    }

    // Property change handlers to auto-save (all commented out for explicit save only)
    // onWeatherCityChanged: saveSettings()
    // onProfileImageChanged: saveSettings()
    // onUseFahrenheitChanged: saveSettings()
    onRandomWallpaperChanged: WallpaperManager.toggleRandomWallpaper()
    onWallpaperIntervalChanged: WallpaperManager.restartRandomWallpaperTimer()
    onWallpaperFolderChanged: WallpaperManager.loadWallpapers()
} 
