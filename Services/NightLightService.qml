pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

Singleton {
  id: root

  // Night Light properties - directly bound to settings
  readonly property var params: Settings.data.nightLight
  // Deprecated overlay flag removed; service only manages wlsunset now
  property bool isActive: false
  property bool isRunning: false
  property string lastCommand: ""
  property var nextCommand: []

  Component.onCompleted: apply()

  function buildCommand() {
    var cmd = ["wlsunset"]
    // Use user-configured temps; if intensity is used, bias lowTemp towards user low
    var i = Math.max(0, Math.min(1, params.intensity))
    var loCfg = params.lowTemp || 3500
    var hiCfg = params.highTemp || 6500
    var lowTemp = Math.round(hiCfg - (hiCfg - loCfg) * Math.pow(i, 0.6))
    cmd.push("-t", lowTemp.toString())
    cmd.push("-T", hiCfg.toString())
    if (params.autoSchedule && LocationService.data.coordinatesReady && LocationService.data.stableLatitude !== "" && LocationService.data.stableLongitude !== "") {
      cmd.push("-l", LocationService.data.stableLatitude)
      cmd.push("-L", LocationService.data.stableLongitude)
    } else {
      // Manual schedule
      if (params.startTime && params.stopTime) {
        cmd.push("-S", params.startTime)
        cmd.push("-s", params.stopTime)
      }
      // Optional: do not pass duration, use wlsunset defaults
    }
    return cmd
  }

  function stopIfRunning() {
    // Best-effort stop; wlsunset runs as foreground, so pkill is simplest
    Quickshell.execDetached(["pkill", "-x", "wlsunset"]) 
    isRunning = false
  }

  function apply() {
    if (!params.enabled) {
      // Disable immediately
      debounceStart.stop()
      nextCommand = []
      stopIfRunning()
      return
    }
    // Debounce rapid changes (slider)
    nextCommand = buildCommand()
    lastCommand = nextCommand.join(" ")
    stopIfRunning()
    debounceStart.restart()
  }

  // Observe setting changes and location readiness
  Connections {
    target: Settings.data.nightLight
    function onEnabledChanged() { apply() }
    function onIntensityChanged() { apply() }
    function onAutoScheduleChanged() { apply() }
    function onStartTimeChanged() { apply() }
    function onStopTimeChanged() { apply() }
  }

  Connections {
    target: LocationService.data
    function onCoordinatesReadyChanged() { if (params.enabled && params.autoSchedule) apply() }
    function onStableLatitudeChanged() { if (params.enabled && params.autoSchedule) apply() }
    function onStableLongitudeChanged() { if (params.enabled && params.autoSchedule) apply() }
  }

  // Foreground process runner
  Process {
    id: runner
    running: false
    onStarted: { isRunning = true; Logger.log("NightLight", "Started wlsunset:", root.lastCommand) }
    onExited: function (code, status) {
      isRunning = false
      Logger.log("NightLight", "wlsunset exited:", code, status)
      // Do not auto-restart here; debounceStart handles starts
    }
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Debounce timer to avoid flicker when moving sliders
  Timer {
    id: debounceStart
    interval: 300
    repeat: false
    onTriggered: {
      if (params.enabled && nextCommand.length > 0) {
        runner.command = nextCommand
        runner.running = true
      }
    }
  }
}
