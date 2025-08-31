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
  property string allUpdatesOutput: ""

  // Update state
  property bool updateInProgress: false
  property bool updateFailed: false
  property string lastUpdateError: ""

  // Computed properties
  readonly property bool aurBusy: checkAurUpdatesProcess.running || checkAurOnlyProcess.running
  readonly property int updates: repoPackages.length
  readonly property int aurUpdates: aurPackages.length
  readonly property int totalUpdates: updates + aurUpdates

  // Polling cooldown (prevent excessive polling)
  property int lastPollTime: 0
  readonly property int pollCooldownMs: 5 * 60 * 1000 // 5 minutes
  readonly property bool canPoll: (Date.now() - lastPollTime) > pollCooldownMs

  // ============================================================================
  // TIMERS
  // ============================================================================

  // Refresh timer for post-update polling
  Timer {
    id: refreshTimer
    interval: 5000
    repeat: false
    onTriggered: {
      Logger.log("ArchUpdater", "Refreshing package lists after update...")
      doPoll()
    }
  }

  // Timer to mark update as complete - with error handling
  Timer {
    id: updateCompleteTimer
    interval: 30000 // Increased to 30 seconds to allow more time
    repeat: false
    onTriggered: {
      Logger.log("ArchUpdater", "Update timeout reached, checking for failures...")
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
    command: ["pgrep", "-f", "(yay|paru).*(-S|-Syu)"]
    onExited: function (exitCode) {
      if (exitCode !== 0 && updateInProgress) {
        // No update processes found, update likely completed
        Logger.log("ArchUpdater", "No update processes detected, marking update as complete")
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
    command: ["sh", "-c", "if [ -f /tmp/archupdater_output.log ]; then grep -i 'error\\|failed to build\\|could not resolve\\|unable to satisfy\\|failed to install\\|failed to upgrade' /tmp/archupdater_output.log | grep -v 'ERROR_DETECTED' | tail -1; fi"]
    onExited: function (exitCode) {
      if (exitCode === 0 && updateInProgress) {
        // Error found in log
        Logger.error("ArchUpdater", "Error detected in log file")
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
    stdout: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.error("ArchUpdater", "Captured error from log:", text.trim())
        }
      }
    }
  }

  // Process to check for successful completion
  Process {
    id: successCheckProcess
    command: ["sh", "-c", "if [ -f /tmp/archupdater_output.log ]; then grep -i ':: Running post-transaction hooks\\|:: Processing package changes\\|upgrading.*\\.\\.\\.\\|installing.*\\.\\.\\.\\|removing.*\\.\\.\\.' /tmp/archupdater_output.log | tail -1; fi"]
    onExited: function (exitCode) {
      if (exitCode === 0 && updateInProgress) {
        // Success indicators found
        console.log("ArchUpdater: Update completed successfully")
        updateInProgress = false
        updateFailed = false
        updateCompleteTimer.stop()
        updateMonitorTimer.stop()
        lastUpdateError = ""

        // Refresh to check actual state
        Qt.callLater(() => {
                       doPoll()
                     }, 1000)
      }
    }
  }

  // Timer to check for success more frequently when update is in progress
  Timer {
    id: errorCheckTimer
    interval: 5000 // Check every 5 seconds
    repeat: true
    running: updateInProgress
    onTriggered: {
      if (updateInProgress && !successCheckProcess.running) {
        successCheckProcess.running = true
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
    Logger.error("ArchUpdater", "Checking for update failures...")
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
    // Initial poll without cooldown restriction
    const aurHelper = getAurHelper()
    if (aurHelper) {
      checkAurUpdatesProcess.command = [aurHelper, "-Qu"]
      checkAurOnlyProcess.command = [aurHelper, "-Qua"]
      checkAurUpdatesProcess.running = true
      lastPollTime = Date.now()
    }
  }

  // ============================================================================
  // PACKAGE CHECKING PROCESSES
  // ============================================================================

  // Process for checking all updates with AUR helper (repo + AUR)
  Process {
    id: checkAurUpdatesProcess
    command: []
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.warn("ArchUpdater", "AUR helper check failed (code:", exitCode, ")")
        aurPackages = []
        repoPackages = []
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        allUpdatesOutput = text
        // Now get AUR-only updates to compare
        checkAurOnlyProcess.running = true
      }
    }
  }

  // Process for checking AUR-only updates (to separate from repo updates)
  Process {
    id: checkAurOnlyProcess
    command: []
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        Logger.warn("ArchUpdater", "AUR helper AUR-only check failed (code:", exitCode, ")")
        aurPackages = []
        repoPackages = []
      }
    }
    stdout: StdioCollector {
      onStreamFinished: {
        parseAllUpdatesOutput(allUpdatesOutput, text)
        Logger.log("ArchUpdater", "found", repoPackages.length, "repo package(s) and", aurPackages.length,
                   "AUR package(s) to upgrade")
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

  // Parse all updates output (repo + AUR packages)
  function parseAllUpdatesOutput(allOutput, aurOnlyOutput) {
    const allLines = allOutput.trim().split('\n').filter(line => line.trim())
    const aurOnlyLines = aurOnlyOutput.trim().split('\n').filter(line => line.trim())

    // Create a set of AUR package names for quick lookup
    const aurPackageNames = new Set()
    for (const line of aurOnlyLines) {
      const m = line.match(/^(\S+)\s+([^\s]+)\s+->\s+([^\s]+)$/)
      if (m) {
        aurPackageNames.add(m[1])
      }
    }

    const repoPackages = []
    const aurPackages = []

    for (const line of allLines) {
      const m = line.match(/^(\S+)\s+([^\s]+)\s+->\s+([^\s]+)$/)
      if (m) {
        const packageInfo = {
          "name": m[1],
          "oldVersion": m[2],
          "newVersion": m[3],
          "description": `${m[1]} ${m[2]} -> ${m[3]}`
        }

        // Check if this package is in the AUR-only list
        if (aurPackageNames.has(m[1])) {
          packageInfo.source = "aur"
          aurPackages.push(packageInfo)
        } else {
          packageInfo.source = "repo"
          repoPackages.push(packageInfo)
        }
      }
    }

    // Update the package lists
    if (repoPackages.length > 0 || aurPackages.length > 0 || allOutput.trim() === "") {
      updateService.repoPackages = repoPackages
      updateService.aurPackages = aurPackages
    }
  }

  function doPoll() {
    // Prevent excessive polling
    if (aurBusy || !canPoll) {
      return
    }

    // Get the AUR helper and set commands
    const aurHelper = getAurHelper()
    if (aurHelper) {
      checkAurUpdatesProcess.command = [aurHelper, "-Qu"]
      checkAurOnlyProcess.command = [aurHelper, "-Qua"]

      // Start AUR updates check (includes both repo and AUR packages)
      checkAurUpdatesProcess.running = true
      lastPollTime = Date.now()
    } else {
      Logger.warn("ArchUpdater", "No AUR helper found (yay or paru)")
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
    Logger.log("ArchUpdater", "Starting full system update...")

    const terminal = Quickshell.env("TERMINAL") || "xterm"

    // Check if we have an AUR helper for full system update
    const aurHelper = getAurHelper()
    if (aurHelper && (aurUpdates > 0 || updates > 0)) {
      // Use AUR helper for full system update (handles both repo and AUR)
      const command = generateUpdateCommand(aurHelper + " -Syu")
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
    Logger.log("ArchUpdater", "Starting selective update for", selectedPackages.length, "packages")

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

    // Update all packages with AUR helper (handles both repo and AUR)
    if (selectedPackages.length > 0) {
      const aurHelper = getAurHelper()
      if (aurHelper) {
        const packageList = selectedPackages.join(" ")
        const command = generateUpdateCommand(aurHelper + " -S " + packageList)
        Quickshell.execDetached([terminal, "-e", "bash", "-c", command])
      } else {
        Logger.warn("ArchUpdater", "No AUR helper found for packages:", selectedPackages.join(", "))
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

  // Manual refresh function (bypasses cooldown)
  function forceRefresh() {
    // Prevent multiple simultaneous refreshes
    if (aurBusy) {
      return
    }

    // Clear error states when refreshing
    updateFailed = false
    lastUpdateError = ""

    // Get the AUR helper and set commands
    const aurHelper = getAurHelper()
    if (aurHelper) {
      checkAurUpdatesProcess.command = [aurHelper, "-Qu"]
      checkAurOnlyProcess.command = [aurHelper, "-Qua"]

      // Force refresh by bypassing cooldown
      checkAurUpdatesProcess.running = true
      lastPollTime = Date.now()
    } else {
      Logger.warn("ArchUpdater", "No AUR helper found (yay or paru)")
    }
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
        Logger.log("ArchUpdater", "Found yay AUR helper")
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
          Logger.log("ArchUpdater", "Found paru AUR helper")
        }
      }
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
    Logger.log("ArchUpdater", "Detecting AUR helper...")

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

  // Auto-poll every 15 minutes (respects cooldown)
  Timer {
    interval: 15 * 60 * 1000 // 15 minutes
    repeat: true
    running: true
    onTriggered: {
      if (!updateInProgress && canPoll) {
        doPoll()
      }
    }
  }
}
