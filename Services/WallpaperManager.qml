pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Settings

Singleton {
    id: manager

    Item {
        Component.onCompleted: {
            loadWallpapers();
            setCurrentWallpaper(currentWallpaper, true);
            toggleRandomWallpaper();
        }
    }
    property string wallpaperDirectory: Settings.wallpaperFolder
    property var wallpaperList: []
    property string currentWallpaper: Settings.currentWallpaper
    property bool scanning: false
    property string transitionType: Settings.transitionType
    property var randomChoices: ["fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "any", "outer"]

    function loadWallpapers() {
        scanning = true;
        wallpaperList = [];
        folderModel.folder = "";
        folderModel.folder = "file://" + (Settings.wallpaperFolder !== undefined ? Settings.wallpaperFolder : "");
    }

    function changeWallpaper(path) {
        if (!Settings.randomWallpaper) {
            setCurrentWallpaper(path);
        }
    }

    function setCurrentWallpaper(path, isInitial) {
        currentWallpaper = path;
        if (!isInitial) {
            Settings.currentWallpaper = path;
            Settings.saveSettings();
        }
        if (Settings.useSWWW) {
            if (Settings.transitionType === "random") {
                transitionType = randomChoices[Math.floor(Math.random() * randomChoices.length)];
            } else {
                transitionType = Settings.transitionType;
            }
            changeWallpaperProcess.running = true;
        }
        generateTheme();
    }

    function setRandomWallpaper() {
        var randomIndex = Math.floor(Math.random() * wallpaperList.length);
        var randomPath = wallpaperList[randomIndex];
        if (!randomPath) {
            return;
        }
        setCurrentWallpaper(randomPath);
    }

    function toggleRandomWallpaper() {
        if (Settings.randomWallpaper && !randomWallpaperTimer.running) {
            randomWallpaperTimer.start();
            setRandomWallpaper();
        } else if (!Settings.randomWallpaper && randomWallpaperTimer.running) {
            randomWallpaperTimer.stop();
        }
    }
    
    function restartRandomWallpaperTimer() {
        if (Settings.randomWallpaper) {
            randomWallpaperTimer.stop();
            randomWallpaperTimer.start();
            setRandomWallpaper();
        }
    }

    function generateTheme() {
        if (Settings.useWallpaperTheme) {
            generateThemeProcess.running = true;
        }
    }

    Timer {
        id: randomWallpaperTimer
        interval: Settings.wallpaperInterval * 1000
        running: false
        repeat: true
        onTriggered: setRandomWallpaper()
        triggeredOnStart: false
    }

    FolderListModel {
        id: folderModel
        nameFilters: ["*.avif", "*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.tga", "*.tiff", "*.webp", "*.bmp", "*.farbfeld"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                var files = [];
                for (var i = 0; i < count; i++) {
                    var fileph = (Settings.wallpaperFolder !== undefined ? Settings.wallpaperFolder : "") + "/" + get(i, "fileName");
                    files.push(fileph);
                }
                wallpaperList = files;
                scanning = false;
            }
        }
    }

    Process {
        id: changeWallpaperProcess
        command: ["swww", "img", "--resize", Settings.wallpaperResize, "--transition-fps", Settings.transitionFps.toString(), "--transition-type", transitionType, "--transition-duration", Settings.transitionDuration.toString(), currentWallpaper]
        running: false
    }
    
    Process {
        id: generateThemeProcess
        command: ["wallust", "run", currentWallpaper, "-u", "-k", "-d", "Templates"]
        workingDirectory: Quickshell.configDir
        running: false
    }
}
