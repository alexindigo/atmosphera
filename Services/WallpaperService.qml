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

  // All available wallpaper transitions
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
    function onDirectoryChanged() {
      root.listWallpapers()
    }
    function onRandomEnabledChanged() {
      root.toggleRandomWallpaper()
    }
    function onRandomIntervalSecChanged() {
      root.restartRandomWallpaperTimer()
    }
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper data
  function getMonitorConfig(screenName) {
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
  // Get specific monitor directory
  function getMonitorDirectory(screenName) {
    var monitor = getMonitorConfig(screenName)
    if (monitor !== undefined && monitor.directory !== undefined) {
      return monitor.directory
    }

    // Fall back to the main/single directory
    return Settings.data.wallpaper.directory
  }

  // -------------------------------------------------------------------
  // Set specific monitor directory
  function setMonitorDirectory(screenName, directory) {
    var monitor = getMonitorConfig(screenName)
    if (monitor !== undefined) {
      monitor.directory = directory
    } else {
      Settings.data.wallpaper.monitors.push({
                                              "name": screenName,
                                              "directory": directory,
                                              "wallpaper": ""
                                            })
    }
  }

  // -------------------------------------------------------------------
  // Get specific monitor wallpaper
  function getWallpaper(screenName) {
    var monitor = getMonitorConfig(screenName)
    if ((monitor !== undefined) && (monitor["wallpaper"] !== undefined)) {
      return monitor["wallpaper"]
    }
    return ""
  }

  // -------------------------------------------------------------------
  function changeWallpaper(screenName, path) {
    if (screenName !== undefined) {
      setWallpaper(screenName, path)
    } else {
      // If no screenName specified change for all screens
      for (var i = 0; i < Quickshell.screens.length; i++) {
        setWallpaper(Quickshell.screens[i].name, path)
      }
    }
  }

  // -------------------------------------------------------------------
  function setWallpaper(screenName, path) {
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
                                              "directory": getMonitorDirectory(screenName),
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
    Logger.log("Wallpaper", "setRandomWallpaper")
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screenName = Quickshell.screens[i].name
      var wallpaperList = getWallpaperList(screenName)

      if (wallpaperList.length > 0) {
        var randomIndex = Math.floor(Math.random() * wallpaperList.length)
        var randomPath = wallpaperList[randomIndex]
        setCurrentWallpaper(screenName, randomPath)
      }
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
  function listWallpapers() {
    if (!Settings.isLoaded) {
      return
    }

    // TODO
    Logger.log("Wallpaper", "Listing wallpapers for all monitors")
    scanning = true
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

  // FolderListModel {
  //   id: folderModel
  //   nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp"]
  //   showDirs: false
  //   sortField: FolderListModel.Name
  //   onStatusChanged: {
  //     if (status === FolderListModel.Ready) {
  //       var files = []
  //       for (var i = 0; i < count; i++) {
  //         var directory = (Settings.data.wallpaper.directory !== undefined ? Settings.data.wallpaper.directory : "")
  //         var filepath = directory + "/" + get(i, "fileName")
  //         files.push(filepath)
  //       }
  //       wallpaperList = files
  //       scanning = false
  //       Logger.log("Wallpaper", "List refreshed, count:", wallpaperList.length)
  //     }
  //   }
  // }
}
