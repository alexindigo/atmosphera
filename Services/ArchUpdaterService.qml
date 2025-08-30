pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: updateService

  // ============================================================================
  // CORE PROPERTIES
  // ============================================================================

  // Package data
  property var repoPackages: []
  property var aurPackages: []
  property var selectedPackages: []
  property int selectedPackagesCount: 0

  // Update state
  property bool updateInProgress: false
  property bool updateFailed: false
  property string lastUpdateError: ""

  // Computed properties
  readonly property bool busy: checkupdatesProcess.running
  readonly property bool aurBusy: checkParuUpdatesProcess.running
  readonly property int updates: repoPackages.length
  readonly property int aurUpdates: aurPackages.length
  readonly property int totalUpdates: updates + aurUpdates

  // ============================================================================
  // TIMERS
  // ============================================================================

  // Refresh timer for post-update polling
  Timer {
    id: refreshTimer
    interval: 5000 // Increased delay to ensure updates complete
    repeat: false
    onTriggered: {
      console.log("ArchUpdater: Refreshing package lists after update...")
      // Just refresh package lists without syncing database
      doPoll()
    }
  }

  // Timer to mark update as complete - with error handling
  Timer {
    id: updateCompleteTimer
    interval: 30000 // Increased to 30 seconds to allow more time
    repeat: false
    onTriggered: {
      console.log("ArchUpdater: Update timeout reached, checking for failures...")
      checkForUpdateFailures()
    }
  }

  // Timer to check if update processes are still running
  Timer {
    id: updateMonitorTimer
    interval: 2000
    repeat: true
    running: updateInProgress
    onTriggered: {
      // Check if any update-related processes might still be running
      checkUpdateStatus()
    }
  }

  // ============================================================================
  // MONITORING PROCESSES
  // ============================================================================

  // Process to monitor update completion
  Process {
    id: updateStatusProcess
    command: ["pgrep", "-f", "(pacman|yay|paru).*(-S|-Syu)"]
    onExited: function (exitCode) {
      if (exitCode !== 0 && updateInProgress) {
        // No update processes found, update likely completed
        console.log("ArchUpdater: No update processes detected, marking update as complete")
        updateInProgress = false
        updateMonitorTimer.stop()

        // Don't stop the complete timer - let it handle failures
        // If the update actually failed, the timer will trigger and set updateFailed = true

        // Refresh package lists after a short delay
        Qt.callLater(() => {
                       doPoll()
                     }, 2000)
      }
    }
  }

  // Process to check for errors in log file (only when update is in progress)
  Process {
    id: errorCheckProcess
    command: ["sh", "-c", "if [ -f /tmp/archupdater_output.log ]; then grep -i 'error\\|failed\\|failed to build\\|ERROR_DETECTED' /tmp/archupdater_output.log | tail -1; fi"]
    onExited: function (exitCode) {
      if (exitCode === 0 && updateInProgress) {
        // Error found in log
        console.log("ArchUpdater: Error detected in log file")
        updateInProgress = false
        updateFailed = true
        updateCompleteTimer.stop()
        updateMonitorTimer.stop()
        lastUpdateError = "Build or update error detected"

        // Refresh to check actual state
        Qt.callLater(() => {
                       doPoll()
                     }, 1000)
      }
    }
  }

  // Timer to check for errors more frequently when update is in progress
  Timer {
    id: errorCheckTimer
    interval: 5000 // Check every 5 seconds
    repeat: true
    running: updateInProgress
    onTriggered: {
      if (updateInProgress && !errorCheckProcess.running) {
        errorCheckProcess.running = true
      }
    }
  }

  // ============================================================================
  // MONITORING FUNCTIONS
  // ============================================================================
  function checkUpdateStatus() {
    if (updateInProgress && !updateStatusProcess.running) {
      updateStatusProcess.running = true
    }
  }

  function checkForUpdateFailures() {
    console.log("ArchUpdater: Checking for update failures...")
    updateInProgress = false
    updateFailed = true
    updateCompleteTimer.stop()
    updateMonitorTimer.stop()

    // Refresh to check actual state after a delay
    Qt.callLater(() => {
                   doPoll()
                 }, 2000)
  }

  // Initial check
  Component.onCompleted: {
    getAurHelper()
    doPoll()
  }

  // ============================================================================
  // PACKAGE CHECKING PROCESSES
  // ============================================================================

  // Process for checking repo updates
  Process {
    id: checkupdatesProcess
    command: ["checkupdates", "--nosync"]
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

  // Process for checking AUR updates with paru specifically
  Process {
    id: checkParuUpdatesProcess
    command: ["paru", "-Qua"]
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.warn("ArchUpdater", "paru check failed (code:", exitCode, ")")
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

  // ============================================================================
  // PARSING FUNCTIONS
  // ============================================================================

  // Generic package parsing function
  function parsePackageOutput(output, source) {
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
                        "source": source
                      })
      }
    }

    // Only update if we have new data or if this is a fresh check
    if (packages.length > 0 || output.trim() === "") {
      if (source === "repo") {
        repoPackages = packages
      } else {
        aurPackages = packages
      }
    }
  }

  // Parse checkupdates output
  function parseCheckupdatesOutput(output) {
    parsePackageOutput(output, "repo")
  }

  // Parse AUR updates output
  function parseAurUpdatesOutput(output) {
    parsePackageOutput(output, "aur")
  }

  function doPoll() {
    // Start repo updates check
    if (!busy) {
      checkupdatesProcess.running = true
    }

    // Start AUR updates check
    if (!aurBusy) {
      checkParuUpdatesProcess.running = true
    }
  }

  // ============================================================================
  // UPDATE FUNCTIONS
  // ============================================================================

  // Helper function to generate update command with error detection
  function generateUpdateCommand(baseCommand) {
    return baseCommand + " 2>&1 | tee /tmp/archupdater_output.log; if [ $? -ne 0 ]; then echo 'ERROR_DETECTED'; fi; echo 'Update complete! Press Enter to close...'; read -p 'Press Enter to continue...'"
  }

  // Update all packages (repo + AUR)
  function runUpdate() {
    if (totalUpdates === 0) {
      doPoll()
      return
    }

    // Reset any previous error states
    updateFailed = false
    lastUpdateError = ""
    updateInProgress = true
    console.log("ArchUpdater: Starting full system update...")

    const terminal = Quickshell.env("TERMINAL") || "xterm"

    // Check if we have an AUR helper for full system update
    const aurHelper = getAurHelper()
    if (aurHelper && (aurUpdates > 0 || updates > 0)) {
      // Use AUR helper for full system update (handles both repo and AUR)
      const command = generateUpdateCommand(aurHelper + " -Syu")
      Quickshell.execDetached([terminal, "-e", "bash", "-c", command])
    } else if (updates > 0) {
      // Fallback to pacman if no AUR helper or only repo updates
      const command = generateUpdateCommand("sudo pacman -Syu")
      Quickshell.execDetached([terminal, "-e", "bash", "-c", command])
    }

    // Start monitoring and timeout timers
    refreshTimer.start()
    updateCompleteTimer.start()
    updateMonitorTimer.start()
  }

  // Update selected packages
  function runSelectiveUpdate() {
    if (selectedPackages.length === 0)
      return

    // Reset any previous error states
    updateFailed = false
    lastUpdateError = ""
    updateInProgress = true
    console.log("ArchUpdater: Starting selective update for", selectedPackages.length, "packages")

    const terminal = Quickshell.env("TERMINAL") || "xterm"

    // Split selected packages by source
    const repoPkgs = []
    const aurPkgs = []

    for (const pkgName of selectedPackages) {
      const repoPkg = repoPackages.find(p => p.name === pkgName)
      if (repoPkg && repoPkg.source === "repo") {
        repoPkgs.push(pkgName)
      }

      const aurPkg = aurPackages.find(p => p.name === pkgName)
      if (aurPkg && aurPkg.source === "aur") {
        aurPkgs.push(pkgName)
      }
    }

    // Update repo packages with sudo
    if (repoPkgs.length > 0) {
      const packageList = repoPkgs.join(" ")
      const command = generateUpdateCommand("sudo pacman -S " + packageList)
      Quickshell.execDetached([terminal, "-e", "bash", "-c", command])
    }

    // Update AUR packages with yay/paru
    if (aurPkgs.length > 0) {
      const aurHelper = getAurHelper()
      if (aurHelper) {
        const packageList = aurPkgs.join(" ")
        const command = generateUpdateCommand(aurHelper + " -S " + packageList)
        Quickshell.execDetached([terminal, "-e", "bash", "-c", command])
      } else {
        Logger.warn("ArchUpdater", "No AUR helper found for packages:", aurPkgs.join(", "))
      }
    }

    // Start monitoring and timeout timers
    refreshTimer.start()
    updateCompleteTimer.start()
    updateMonitorTimer.start()
  }

  // Reset update state (useful for manual recovery)
  function resetUpdateState() {
    // If update is in progress, mark it as failed first
    if (updateInProgress) {
      updateFailed = true
    }

    updateInProgress = false
    lastUpdateError = ""
    updateCompleteTimer.stop()
    updateMonitorTimer.stop()
    refreshTimer.stop()

    // Refresh to get current state
    doPoll()
  }

  // Manual refresh function
  function forceRefresh() {
    // Prevent multiple simultaneous refreshes
    if (busy || aurBusy) {
      return
    }

    // Clear error states when refreshing
    updateFailed = false
    lastUpdateError = ""

    // Just refresh the package lists without syncing databases
    doPoll()
  }

  // ============================================================================
  // UTILITY PROCESSES
  // ============================================================================

  // Process for checking yay availability
  Process {
    id: yayCheckProcess
    command: ["which", "yay"]
    onExited: function (exitCode) {
      if (exitCode === 0) {
        cachedAurHelper = "yay"
      }
    }
  }

  // Process for checking paru availability
  Process {
    id: paruCheckProcess
    command: ["which", "paru"]
    onExited: function (exitCode) {
      if (exitCode === 0) {
        if (cachedAurHelper === "") {
          cachedAurHelper = "paru"
        }
      }
    }
  }

  // Process for syncing package databases with sudo
  Process {
    id: syncDatabaseProcess
    command: ["sudo", "pacman", "-Sy"]
    onStarted: {
      console.log("ArchUpdater: Starting database sync with sudo...")
    }
    onExited: function (exitCode) {
      console.log("ArchUpdater: Database sync exited with code:", exitCode)
      if (exitCode === 0) {
        console.log("ArchUpdater: Database sync successful")
      } else {
        console.log("ArchUpdater: Database sync failed")
      }

      // After sync completes, wait a moment then refresh package lists
      console.log("ArchUpdater: Database sync complete, waiting before refresh...")
      Qt.callLater(() => {
                     console.log("ArchUpdater: Refreshing package lists after database sync...")
                     doPoll()
                   }, 2000)
    }
  }

  // Cached AUR helper detection
  property string cachedAurHelper: ""

  // Helper function to detect AUR helper
  function getAurHelper() {
    // Return cached result if available
    if (cachedAurHelper !== "") {
      return cachedAurHelper
    }

    // Check for AUR helpers using Process objects
    console.log("ArchUpdater: Detecting AUR helper...")

    // Start the detection processes
    yayCheckProcess.running = true
    paruCheckProcess.running = true

    // For now, return a default (will be updated by the processes)
    // In a real implementation, you'd want to wait for the processes to complete
    return "paru" // Default fallback
  }

  // ============================================================================
  // PACKAGE SELECTION FUNCTIONS
  // ============================================================================
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

  // ============================================================================
  // REFRESH FUNCTIONS
  // ============================================================================

  // Function to manually sync package databases (separate from refresh)
  function syncPackageDatabases() {
    console.log("ArchUpdater: Manual database sync requested...")
    const terminal = Quickshell.env("TERMINAL") || "xterm"
    const command = "sudo pacman -Sy && echo 'Database sync complete! Press Enter to close...' && read -p 'Press Enter to continue...'"
    console.log("ArchUpdater: Executing sync command:", command)
    console.log("ArchUpdater: Terminal:", terminal)
    Quickshell.execDetached([terminal, "-e", "bash", "-c", command])
  }

  // Function to force a complete refresh (sync + check)
  function forceCompleteRefresh() {
    console.log("ArchUpdater: Force complete refresh requested...")

    // Start database sync process (will trigger refresh when complete)
    console.log("ArchUpdater: Starting complete refresh process...")
    syncDatabaseProcess.running = true
  }

  // Function to sync database and refresh package lists
  function syncDatabaseAndRefresh() {
    console.log("ArchUpdater: Syncing database and refreshing package lists...")

    // Start database sync process (will trigger refresh when complete)
    console.log("ArchUpdater: Starting database sync process...")
    syncDatabaseProcess.running = true
  }

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  // Notification helper
  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "UpdateService", "-i", "system-software-update", title, body])
  }

  // ============================================================================
  // AUTO-POLL TIMER
  // ============================================================================

  // Auto-poll every 15 minutes
  Timer {
    interval: 15 * 60 * 1000 // 15 minutes
    repeat: true
    running: true
    onTriggered: {
      if (!updateInProgress) {
        doPoll()
      }
    }
  }
}
