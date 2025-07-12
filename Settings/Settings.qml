pragma Singleton
import QtQuick
import QtCore

QtObject {
    property string weatherCity: "Dinslaken"
    property string profileImage: "https://cdn.discordapp.com/avatars/158005126638993408/de403f05fd7f74bb17e01a9b066a30fa?size=64"
    property bool useFahrenheit
    property string wallpaperFolder: "/home/lysec/nixos/assets/wallpapers" // Default path, make persistent
    property string currentWallpaper: ""
    property string videoPath: "~/Videos/" // Default path, make persistent

    // Settings persistence
    property var settings: Qt.createQmlObject('import QtCore; Settings { category: "Quickshell" }', this, "settings")

    Component.onCompleted: {
        loadSettings()
    }

    function loadSettings() {
        let wc = settings.value("weatherCity", "Dinslaken");
        weatherCity = (wc !== undefined && wc !== null) ? wc : "Dinslaken";
        let pi = settings.value("profileImage", "https://cdn.discordapp.com/avatars/158005126638993408/de403f05fd7f74bb17e01a9b066a30fa?size=64");
        profileImage = (pi !== undefined && pi !== null) ? pi : "https://cdn.discordapp.com/avatars/158005126638993408/de403f05fd7f74bb17e01a9b066a30fa?size=64";
        let tempUnit = settings.value("weatherTempUnit", "celsius")
        useFahrenheit = (tempUnit === "fahrenheit")
        wallpaperFolder = settings.value("wallpaperFolder", "/home/lysec/nixos/assets/wallpapers")
        currentWallpaper = settings.value("currentWallpaper", "")
        videoPath = settings.value("videoPath", "/home/lysec/Videos")
        console.log("Loaded profileImage:", profileImage)
    }

    function saveSettings() {
        settings.setValue("weatherCity", weatherCity)
        settings.setValue("profileImage", profileImage)
        settings.setValue("weatherTempUnit", useFahrenheit ? "fahrenheit" : "celsius")
        settings.setValue("wallpaperFolder", wallpaperFolder)
        settings.setValue("currentWallpaper", currentWallpaper)
        settings.setValue("videoPath", videoPath)
        settings.sync()
        console.log("Saving profileImage:", profileImage)
    }

    // Property change handlers to auto-save (all commented out for explicit save only)
    // onWeatherCityChanged: saveSettings()
    // onProfileImageChanged: saveSettings()
    // onUseFahrenheitChanged: saveSettings()
} 