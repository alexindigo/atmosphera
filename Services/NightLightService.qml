pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Night Light properties - directly bound to settings
  readonly property var params: Settings.data.nightLight

  // Computed properties
  readonly property color overlayColor: params.enabled ? calculateOverlayColor() : "transparent"
  property bool isActive: params.enabled && (params.autoSchedule ? isWithinSchedule() : true)

  Component.onCompleted: {
    Logger.log("NightLight", "Service started")
  }

  function calculateOverlayColor() {
    if (!isActive) {
      return "transparent"
    }

    // More vibrant color formula - stronger effect at high warmth
    var red = 1.0
    var green = 1.0 - (0.43 * params.intensity)
    var blue = 1.0 - (0.84 * params.intensity)
    var alpha = (params.intensity * 0.25) // Higher alpha for more noticeable effect

    return Qt.rgba(red, green, blue, alpha)
  }

  function isWithinSchedule() {
    if (!params.autoSchedule) {
      return true
    }

    var now = new Date()
    var currentTime = now.getHours() * 60 + now.getMinutes()

    var startParts = params.startTime.split(":")
    var stopParts = params.stopTime.split(":")
    var startMinutes = parseInt(startParts[0]) * 60 + parseInt(startParts[1])
    var stopMinutes = parseInt(stopParts[0]) * 60 + parseInt(stopParts[1])

    // Handle overnight schedule (e.g., 20:00 to 07:00)
    if (stopMinutes < startMinutes) {
      return currentTime >= startMinutes || currentTime <= stopMinutes
    } else {
      return currentTime >= startMinutes && currentTime <= stopMinutes
    }
  }

  // Timer to check schedule changes
  Timer {
    interval: 60000 // Check every minute
    running: params.enabled && params.autoSchedule
    repeat: true
    onTriggered: {
      isActive = isWithinSchedule()
    }
  }
}
