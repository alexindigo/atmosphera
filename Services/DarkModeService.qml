pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services

Singleton {
  id: root

  property bool initComplete: false
  property bool nextDarkModeState: false

  Connections {
    target: LocationService.data
    function onWeatherChanged() {
      if (LocationService.data.weather !== null) {
        const changes = root.collectChanges(LocationService.data.weather)
        if (!root.initComplete) {
          root.initComplete = true
          root.resetDarkMode(changes)
        }
        root.scheduleChange(changes)
      }
    }
  }

  Timer {
    id: timer
    onTriggered: {
      Settings.data.colorSchemes.darkMode = root.nextDarkModeState
      if (LocationService.data.weather !== null) {
        const changes = root.collectChanges(LocationService.data.weather)
        root.scheduleChange(changes)
      }
    }
  }

  function collectChanges(weather) {
    const changes = []
    for (var i = 0; i < weather.daily.sunrise.length; i++) {
      changes.push({
                     "time": Date.parse(weather.daily.sunrise[i]),
                     "darkMode": false
                   })
      changes.push({
                     "time": Date.parse(weather.daily.sunset[i]),
                     "darkMode": true
                   })
    }
    return changes
  }

  function resetDarkMode(changes) {
    const now = Date.now()

    // changes.findLast(change => change.time < now) // not available in QML...
    let lastChange = null
    for (var i = 0; i < changes.length; i++) {
      if (changes[i].time < now) {
        lastChange = changes[i]
      }
    }

    if (lastChange) {
      Settings.data.colorSchemes.darkMode = lastChange.darkMode
      Logger.log("DarkModeService", `Reset: darkmode=${lastChange.darkMode}`)
    }
  }

  function scheduleChange(changes) {
    const now = Date.now()
    const nextChange = changes.find(change => change.time > now)
    if (nextChange) {
      root.nextDarkModeState = nextChange.darkMode
      timer.interval = nextChange.time - now
      timer.restart()
      Logger.log("DarkModeService", `Scheduled: darkmode=${nextChange.darkMode} in ${timer.interval} ms`)
    }
  }

  function init() {
    Logger.log("DarkModeService", "Service started")
  }
}
