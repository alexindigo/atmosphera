pragma Singleton

import QtQuick
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Public properties
  property string baseVersion: "v2.5.0"
  property bool isRelease: false

  property string currentVersion: isRelease ? baseVersion : baseVersion + "-dev"

  // Internal helpers
  function getVersion() {
    return root.currentVersion
  }

  function checkForUpdates() {
    // TODO: Implement update checking logic
    Logger.log("UpdateService", "Checking for updates...")
  }

  function init() {
    // Ensure the singleton is created
    Logger.log("UpdateService", "Version:", root.currentVersion)
  }
}
