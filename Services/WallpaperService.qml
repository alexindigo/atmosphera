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
      key: "random"
      name: "Random"
    }
    ListElement {
      key: "fade"
      name: "Fade"
    }
    ListElement {
      key: "disc"
      name: "Disc"
    }
    ListElement {
      key: "wipe_left"
      name: "Wipe Left"
    }
    ListElement {
      key: "wipe_right"
      name: "Wipe Right"
    }
    ListElement {
      key: "wipe_up"
      name: "Wipe Up"
    }
    ListElement {
      key: "wipe_down"
      name: "Wipe Down"
    }
  }

  // All transition keys but filter out "random"
  readonly property var allTransitions: Array.from({
                                                     "length": transitionsModel.count
                                                   }, (_, i) => transitionsModel.get(i).key).filter(
                                          key => key !== "random" && key != "none")

  property var wallpaperLists: ({})
  property int scanningCount: 0
  readonly property bool scanning: (scanningCount > 0)

  Connections {
    target: Settings.data.wallpaper
    function onDirectoryChanged() {
      root.refreshWallpapersList()
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
    if (!Settings.data.wallpaper.enableMultiMonitorDirectories) {
      return Settings.data.wallpaper.directory
    }

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
      Logger.warn("Wallpaper", "setWallpaper", "no screen specified")
      return
    }

    Logger.log("Wallpaper", "setWallpaper on", screenName, ": ", path)

    var wallpaperChanged = false

    var monitor = getMonitorConfig(screenName)
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

    if (Settings.data.wallpaper.enableMultiMonitorDirectories) {
      // Pick a random wallpaper per screen
      for (var i = 0; i < Quickshell.screens.length; i++) {
        var screenName = Quickshell.screens[i].name
        var wallpaperList = getWallpapersList(screenName)

        if (wallpaperList.length > 0) {
          var randomIndex = Math.floor(Math.random() * wallpaperList.length)
          var randomPath = wallpaperList[randomIndex]
          changeWallpaper(screenName, randomPath)
        }
      }
    } else {
      // Pick a random wallpaper common to all screens
      // We can use any screenName here, so we just pick the primary one.
      var wallpaperList = getWallpapersList(Screen.name)
      if (wallpaperList.length > 0) {
        var randomIndex = Math.floor(Math.random() * wallpaperList.length)
        var randomPath = wallpaperList[randomIndex]
        changeWallpaper(undefined, randomPath)
      }
    }
  }

  // -------------------------------------------------------------------
  function toggleRandomWallpaper() {
    Logger.log("Wallpaper", "toggleRandomWallpaper")
    if (Settings.data.wallpaper.randomEnabled) {
      randomWallpaperTimer.restart()
      setRandomWallpaper()
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
  function getWallpapersList(screenName) {
    if (screenName != undefined && wallpaperLists[screenName] != undefined) {
      return wallpaperLists[screenName]
    }
    return []
  }

  // -------------------------------------------------------------------
  function refreshWallpapersList() {
    Logger.log("Wallpaper", "refreshWallpapersList")
    scanningCount = 0

    // Force refresh by toggling the folder property on each FolderListModel
    for (var i = 0; i < wallpaperScanners.count; i++) {
      var scanner = wallpaperScanners.objectAt(i)
      if (scanner) {
        var currentFolder = scanner.folder
        scanner.folder = ""
        scanner.folder = currentFolder
      }
    }
  }

  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  // -------------------------------------------------------------------
  Timer {
    id: randomWallpaperTimer
    interval: Settings.data.wallpaper.randomIntervalSec * 1000
    running: Settings.data.wallpaper.randomEnabled
    repeat: true
    onTriggered: setRandomWallpaper()
    triggeredOnStart: false
  }

  // Instantiator (not Repeater) to create FolderListModel for each monitor
  Instantiator {
    id: wallpaperScanners
    model: Quickshell.screens
    delegate: FolderListModel {
      property string screenName: modelData.name

      folder: "file://" + root.getMonitorDirectory(screenName)
      nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.pnm", "*.bmp"]
      showDirs: false
      sortField: FolderListModel.Name
      onStatusChanged: {
        if (status === FolderListModel.Null) {
          // Flush the list
          var lists = root.wallpaperLists
          lists[screenName] = []
          root.wallpaperLists = lists
        } else if (status === FolderListModel.Loading) {
          // Flush the list
          var lists = root.wallpaperLists
          lists[screenName] = []
          root.wallpaperLists = lists

          scanningCount++
        } else if (status === FolderListModel.Ready) {
          var files = []
          for (var i = 0; i < count; i++) {
            var directory = root.getMonitorDirectory(screenName)
            var filepath = directory + "/" + get(i, "fileName")
            files.push(filepath)
          }

          var lists = root.wallpaperLists
          lists[screenName] = files
          root.wallpaperLists = lists

          scanningCount--
          Logger.log("Wallpaper", "List refreshed for", screenName, "count:", files.length)
        }
      }
    }
  }
}
