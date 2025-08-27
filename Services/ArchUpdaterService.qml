pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: updateService

  // Core properties
  readonly property bool busy: checkupdatesProcess.running
  readonly property bool aurBusy: checkAurUpdatesProcess.running
  readonly property int updates: repoPackages.length
  readonly property int aurUpdates: aurPackages.length
  readonly property int totalUpdates: updates + aurUpdates
  property var repoPackages: []
  property var aurPackages: []
  property var selectedPackages: []
  property int selectedPackagesCount: 0
  property bool updateInProgress: false

  // Initial check
  Component.onCompleted: {
    doPoll()
    doAurPoll()
  }

  // Process for checking repo updates
  Process {
    id: checkupdatesProcess
    command: ["checkupdates"]
    onExited: function (exitCode) {
      if (exitCode !== 0 && exitCode !== 2) {
        Logger.warn("ArchUpdater", "checkupdates failed (code:", exitCode, ")")
        repoPackages = []
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        parseCheckupdatesOutput(text)
        Logger.log("ArchUpdater", "found", repoPackages.length, "repo package(s) to upgrade")
      }
    }
  }

  // Process for checking AUR updates
  Process {
    id: checkAurUpdatesProcess
    command: ["sh", "-c", "command -v yay >/dev/null 2>&1 && yay -Qua || command -v paru >/dev/null 2>&1 && paru -Qua || echo ''"]
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.warn("ArchUpdater", "AUR check failed (code:", exitCode, ")")
        aurPackages = []
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        parseAurUpdatesOutput(text)
        Logger.log("ArchUpdater", "found", aurPackages.length, "AUR package(s) to upgrade")
      }
    }
  }

  // Parse checkupdates output
  function parseCheckupdatesOutput(output) {
    const lines = output.trim().split('\n').filter(line => line.trim())
    const packages = []

    for (const line of lines) {
      const m = line.match(/^(\S+)\s+([^\s]+)\s+->\s+([^\s]+)$/)
      if (m) {
        packages.push({
                        "name": m[1],
                        "oldVersion": m[2],
                        "newVersion": m[3],
                        "description": `${m[1]} ${m[2]} -> ${m[3]}`,
                        "source": "repo"
                      })
      }
    }

    repoPackages = packages
  }

  // Parse AUR updates output
  function parseAurUpdatesOutput(output) {
    const lines = output.trim().split('\n').filter(line => line.trim())
    const packages = []

    for (const line of lines) {
      const m = line.match(/^(\S+)\s+([^\s]+)\s+->\s+([^\s]+)$/)
      if (m) {
        packages.push({
                        "name": m[1],
                        "oldVersion": m[2],
                        "newVersion": m[3],
                        "description": `${m[1]} ${m[2]} -> ${m[3]}`,
                        "source": "aur"
                      })
      }
    }

    aurPackages = packages
  }

  // Check for updates
  function doPoll() {
    if (busy)
      return
    checkupdatesProcess.running = true
  }

  // Check for AUR updates
  function doAurPoll() {
    if (aurBusy)
      return
    checkAurUpdatesProcess.running = true
  }

  // Update all packages (repo + AUR)
  function runUpdate() {
    if (totalUpdates === 0) {
      doPoll()
      doAurPoll()
      return
    }

    updateInProgress = true
    // Update repos first, then AUR
    Quickshell.execDetached(["pkexec", "pacman", "-Syu", "--noconfirm"])
    Quickshell.execDetached(
          ["sh", "-c", "command -v yay >/dev/null 2>&1 && yay -Sua --noconfirm || command -v paru >/dev/null 2>&1 && paru -Sua --noconfirm || true"])

    // Refresh after updates with multiple attempts
    refreshAfterUpdate()
  }

  // Update selected packages
  function runSelectiveUpdate() {
    if (selectedPackages.length === 0)
      return

    updateInProgress = true
    // Split selected packages by source
    const repoPkgs = selectedPackages.filter(pkg => {
                                               const repoPkg = repoPackages.find(p => p.name === pkg)
                                               return repoPkg && repoPkg.source === "repo"
                                             })
    const aurPkgs = selectedPackages.filter(pkg => {
                                              const aurPkg = aurPackages.find(p => p.name === pkg)
                                              return aurPkg && aurPkg.source === "aur"
                                            })

    // Update repo packages
    if (repoPkgs.length > 0) {
      const repoCommand = ["pkexec", "pacman", "-S", "--noconfirm"].concat(repoPkgs)
      Quickshell.execDetached(repoCommand)
    }

    // Update AUR packages
    if (aurPkgs.length > 0) {
      const aurCommand = ["sh", "-c", `command -v yay >/dev/null 2>&1 && yay -S ${aurPkgs.join(
                            ' ')} --noconfirm || command -v paru >/dev/null 2>&1 && paru -S ${aurPkgs.join(
                            ' ')} --noconfirm || true`]
      Quickshell.execDetached(aurCommand)
    }

    // Clear selection and refresh
    selectedPackages = []
    selectedPackagesCount = 0
    refreshAfterUpdate()
  }

  // Package selection functions
  function togglePackageSelection(packageName) {
    const index = selectedPackages.indexOf(packageName)
    if (index > -1) {
      selectedPackages.splice(index, 1)
    } else {
      selectedPackages.push(packageName)
    }
    selectedPackagesCount = selectedPackages.length
  }

  function selectAllPackages() {
    selectedPackages = [...repoPackages.map(pkg => pkg.name), ...aurPackages.map(pkg => pkg.name)]
    selectedPackagesCount = selectedPackages.length
  }

  function deselectAllPackages() {
    selectedPackages = []
    selectedPackagesCount = 0
  }

  function isPackageSelected(packageName) {
    return selectedPackages.indexOf(packageName) > -1
  }

  // Robust refresh after updates
  function refreshAfterUpdate() {
    // First refresh attempt after 3 seconds
    Qt.callLater(() => {
                   doPoll()
                   doAurPoll()
                 }, 3000)

    // Second refresh attempt after 8 seconds
    Qt.callLater(() => {
                   doPoll()
                   doAurPoll()
                 }, 8000)

    // Third refresh attempt after 15 seconds
    Qt.callLater(() => {
                   doPoll()
                   doAurPoll()
                   updateInProgress = false
                 }, 15000)

    // Final refresh attempt after 30 seconds
    Qt.callLater(() => {
                   doPoll()
                   doAurPoll()
                 }, 30000)
  }

  // Notification helper
  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "UpdateService", "-i", "system-software-update", title, body])
  }

  // Auto-poll every 15 minutes
  Timer {
    interval: 15 * 60 * 1000 // 15 minutes
    repeat: true
    running: true
    onTriggered: {
      doPoll()
      doAurPoll()
    }
  }
}
