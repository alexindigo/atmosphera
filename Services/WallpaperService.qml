pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  Component.onCompleted: {
    Logger.log("Wallpaper", "Service started")
  }

  readonly property ListModel transitionsModel: ListModel {
    ListElement {
      key: "none"
      name: "None"
    }
    ListElement {
      key: "fade"
      name: "Fade"
    }
  }

  property var wallpaperList: []
  property bool scanning: false

  Connections {
    target: Settings.data.wallpaper
    function onDirectoryChanged() { console.log("ondirchanged") ; root.listWallpapers() }
    function onRandomEnabledChanged() { root.toggleRandomWallpaper() }
    function onRandomIntervalSecChanged() { root.restartRandomWallpaperTimer() }
  }

  // -------------------------------------------------------------------
  function geMonitorDefinition(screenName) {
    var monitors = Settings.data.wallpaper.monitors
    if (monitors !== undefined) {
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i].name !== undefined && monitors[i].name === screenName) {
          return monitors[i]
        }
      }
    }
  }

  // -------------------------------------------------------------------
  function getMonitorWallpaperDirectory(screenName) {
    var monitor = geMonitorDefinition(screenName)
    if (monitor !== undefined) {
      return monitor.directory
    }
    return Settings.data.wallpaper.directory
  }

  // -------------------------------------------------------------------
  function setMonitorWallpaperDirectory(screenName, directory) {
    var monitor = geMonitorDefinition(screenName)
    if (monitor !== undefined) {
      monitor.directory = directory
      return
    }

    Settings.data.wallpaper.monitors.push({
                                            "name": screenName,
                                            "directory": directory,
                                            "wallpaper": ""
                                          })
  }

  // -------------------------------------------------------------------
  function listWallpapers() {
    Logger.log("Wallpaper", "Listing wallpapers")
    scanning = true
    wallpaperList = []
    // Set the folder directly to avoid model reset issues
    folderModel.folder = "file://" + (Settings.data.wallpaper.directory !== undefined ? Settings.data.wallpaper.directory : "")
  }

  // -------------------------------------------------------------------
  function getWallpaper(screenName) {
    // Logger.log("Wallpaper", "getWallpaper on", screenName)
    var monitor = geMonitorDefinition(screenName)
    if ((monitor !== undefined) && (monitor["wallpaper"] !== undefined)) {
      return monitor["wallpaper"]
    }
    return ""
  }

  // -------------------------------------------------------------------
  function changeWallpaper(screenName, path) {
    Logger.log("Changing wallpaper")
    if (screenName !== undefined) {
      setCurrentWallpaper(screenName, path)
    } else {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        setCurrentWallpaper(Quickshell.screens[i].name, path, false)
      }
    }
  }

  // -------------------------------------------------------------------
  function setCurrentWallpaper(screenName, path) {
    if (path === "" || path === undefined) {
      return
    }
    
    if (screenName === undefined) {
      Logger.warn("Wallpaper", "setCurrentWallpaper", "no screen specified")
      return
    }

    Logger.log("Wallpaper", "setCurrentWallpaper on", screenName, ": ", path)

    var wallpaperChanged = false

    var monitor = geMonitorDefinition(screenName)
    if (monitor !== undefined) {
      wallpaperChanged = (monitor["wallpaper"] !== path)
      monitor["wallpaper"] = path
    } else {
      wallpaperChanged = true
      Settings.data.wallpaper.monitors.push({
                                              "name": screenName,
                                              "directory": Settings.data.wallpaper.directory,
                                              "wallpaper": path
                                            })                  
    }

    // Restart the random wallpaper timer
    if (randomWallpaperTimer.running) {
      randomWallpaperTimer.restart()
    }

    // Notify ColorScheme service if the wallpaper actually changed
    if (wallpaperChanged) {
      ColorSchemeService.changedWallpaper()
    }
  }

  // -------------------------------------------------------------------
  function setRandomWallpaper() {
    Logger.log("Wallpaper", "setRandomWallpaper");
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screenName = Quickshell.screens[i].name
      // TODO one list per monitor
      var randomIndex = Math.floor(Math.random() * wallpaperList.length)
      var randomPath = wallpaperList[randomIndex]
      setCurrentWallpaper(screenName, randomPath)
    }
  }

  // -------------------------------------------------------------------
  function toggleRandomWallpaper() {
    Logger.log("Wallpaper", "toggleRandomWallpaper")
    if (Settings.data.wallpaper.randomEnabled && !randomWallpaperTimer.running) {
      randomWallpaperTimer.start()
      setRandomWallpaper()
    } else if (!Settings.data.wallpaper.randomEnabled && randomWallpaperTimer.running) {
      randomWallpaperTimer.stop()
    }
  }

  // -------------------------------------------------------------------
  function restartRandomWallpaperTimer() {
    if (Settings.data.wallpaper.isRandom) {
      randomWallpaperTimer.stop()
      randomWallpaperTimer.start()
    }
  }

  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  Timer {
    id: randomWallpaperTimer
    interval: Settings.data.wallpaper.randomIntervalSec * 1000
    running: false
    repeat: true
    onTriggered: setRandomWallpaper()
    triggeredOnStart: false
  }

  FolderListModel {
    id: folderModel
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp"]
    showDirs: false
    sortField: FolderListModel.Name
    onStatusChanged: {
      if (status === FolderListModel.Ready) {
        var files = []
        for (var i = 0; i < count; i++) {
          var directory = (Settings.data.wallpaper.directory !== undefined ? Settings.data.wallpaper.directory : "")
          var filepath = directory + "/" + get(i, "fileName")
          files.push(filepath)
        }
        wallpaperList = files
        scanning = false
        Logger.log("Wallpaper", "List refreshed, count:", wallpaperList.length)
      }
    }
  }
}
