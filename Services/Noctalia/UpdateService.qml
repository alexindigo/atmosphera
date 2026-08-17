pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  // Version properties
  // currentVersion is detected at init (real installed version):
  //   1. <shellDir>/VERSION — written by the package at build time (pkgver)
  //   2. git describe of the shell dir — dev checkouts
  //   3. the hardcoded fallback below — source builds / other distros
  readonly property string baseVersion: "0.1.0"
  readonly property string developmentSuffix: "-git"
  readonly property string fallbackVersion: `v${baseVersion + developmentSuffix}`

  // Noctalia API banner for plugin minNoctaliaVersion checks (install +
  // update): a plugin is compatible when its declared major version is at or
  // below this ceiling — i.e. the whole Noctalia v4 line and older, any
  // minor/patch. The v4 line is closed upstream (they moved to v5), so this
  // is a fixed fact, not a version number that can go stale. Distinct from
  // baseVersion, which is only the display fallback for version detection.
  // Atmosphera-native plugins use minAtmospheraVersion instead, checked
  // against the real fork version (see currentVersion).
  readonly property int noctaliaCompatMajor: 4

  property string currentVersion: fallbackVersion
  // True once versionDetectProcess produced a real version (VERSION file or git
  // describe). While false, currentVersion is fallbackVersion, built from
  // baseVersion ("0.1.0") — NOT a real version. Compatibility gates must not
  // compare against it; that is precisely the original "every plugin is
  // incompatible" bug, where baseVersion was the operand too.
  property bool versionKnown: false
  property bool isGitVersion: true
  // True when the version came from the packaged VERSION file (real installs).
  // The update check only makes sense for packaged installs — dev checkouts
  // manage their own git state and would false-positive when ahead of origin.
  property bool versionFromPackage: false

  // Classify a version string as a -git/dev build (drives the update-check
  // channel: commit-hash comparison for git builds, release tags otherwise)
  function classifyIsGitVersion(v) {
    return /\.r\d+\.g[0-9a-f]+/.test(v) || /-\d+-g[0-9a-f]+/.test(v) || v.endsWith("-dirty") || v.endsWith(developmentSuffix);
  }

  // Extract the commit hash from a -git style version (pkgver g<hash> or
  // describe -g<hash>); "" when not a git build
  function versionCommitHash(v) {
    var m = v.match(/\.g([0-9a-f]{7,})/) || v.match(/-g([0-9a-f]{7,})/);
    return m ? m[1] : "";
  }

  Process {
    id: versionDetectProcess
    command: ["sh", "-c", `if [ -f "${Quickshell.shellDir}/VERSION" ]; then echo "pkg:$(cat "${Quickshell.shellDir}/VERSION")"; elif [ -d "${Quickshell.shellDir}/.git" ]; then echo "git:$(git -C "${Quickshell.shellDir}" describe --tags --always --dirty 2>/dev/null)"; fi`]
    running: false

    onExited: function (exitCode) {
      var detected = stdout.text.trim();
      var fromPackage = detected.startsWith("pkg:");
      if (fromPackage || detected.startsWith("git:")) {
        detected = detected.substring(4);
      }
      if (detected !== "") {
        // Strip pacman pkgrel suffix ("...-1") from packaged versions
        var stripped = detected.replace(/-\d+$/, "");
        root.currentVersion = stripped;
        root.versionKnown = true;
        root.isGitVersion = root.classifyIsGitVersion(stripped);
        root.versionFromPackage = fromPackage;
        Logger.i("UpdateService", "Detected installed version:", stripped, "(git:", root.isGitVersion + ", packaged:", root.versionFromPackage + ")");
      } else {
        Logger.i("UpdateService", "No VERSION file or git describe — using fallback version:", root.currentVersion);
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // URLs
  readonly property string upgradeLogBaseUrl: Quickshell.env("ATMOSPHERA_UPGRADELOG_URL") || ""

  // Changelog properties
  property bool initialized: false
  property bool changelogPending: false
  property string changelogFromVersion: ""
  property string changelogToVersion: ""
  property string previousVersion: ""
  property string changelogCurrentVersion: ""
  property string releaseContent: ""
  property string lastShownVersion: ""
  property bool popupScheduled: false
  property string fetchError: ""
  property string changelogLastSeenVersion: ""
  property bool changelogStateLoaded: false
  property bool pendingShowRequest: false

  // Fix for FileView race condition
  property bool saveInProgress: false
  property bool pendingSave: false
  property int saveDebounceTimer: 0

  Connections {
    target: PanelService
    function onPopupMenuWindowRegistered(screen) {
      if (popupScheduled) {
        if (!viewChangelogTargetScreen || viewChangelogTargetScreen.name === screen.name) {
          openWhenReady();
        }
      }
    }
  }

  signal popupQueued(string fromVersion, string toVersion)

  function init() {
    if (initialized)
      return;

    initialized = true;
    versionDetectProcess.running = true;

    // Load changelog state from ShellState
    Qt.callLater(() => {
      if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
        loadChangelogState();
      }
    });
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadChangelogState();
      }
    }
  }

  // Debounce timer to prevent rapid successive saves
  Timer {
    id: saveDebouncer
    interval: 300
    repeat: false
    onTriggered: executeSave()
  }

  function handleChangelogRequest() {
    const fromVersion = changelogFromVersion || "";
    const toVersion = changelogToVersion || "";

    if (Settings.shouldOpenSetupWizard) {
      // If you'll see the setup wizard then you don't need to see the changelog
      markChangelogSeen(toVersion);
      return;
    }

    if (!toVersion)
      return;

    if (popupScheduled && changelogCurrentVersion === toVersion)
      return;

    if (!popupScheduled && lastShownVersion === toVersion)
      return;

    previousVersion = fromVersion;
    changelogCurrentVersion = toVersion;

    // Fetch the upgrade log from the server
    fetchUpgradeLog(fromVersion, toVersion);

    popupScheduled = true;
    root.popupQueued(previousVersion, changelogCurrentVersion);

    clearChangelogRequest();
  }

  function fetchUpgradeLog(fromVersion, toVersion) {
    // Normalize and ensure "v" prefix for consistent URL format
    let from = ensureVersionPrefix(fromVersion || changelogLastSeenVersion || "3.0.0");
    let to = ensureVersionPrefix(toVersion);

    // Strip -git suffix
    from = from.replace(root.developmentSuffix, "");
    to = to.replace(root.developmentSuffix, "");

    // 'from' always needs to be before 'to' (use semantic comparison)
    if (compareVersions(from, to) >= 0) {
      from = "v3.0.0";
    }

    const url = `${upgradeLogBaseUrl}/${from}/${to}`;
    Logger.i("UpdateService", "Fetching upgrade log:", url);
    const request = new XMLHttpRequest();
    request.onreadystatechange = function () {
      if (request.readyState === XMLHttpRequest.DONE) {
        Logger.d("UpdateService", "Request completed with status:", request.status);
        Logger.d("UpdateService", "Response text length:", request.responseText ? request.responseText.length : 0);

        if (request.status >= 200 && request.status < 300) {
          releaseContent = request.responseText || "";
          Logger.d("UpdateService", "Successfully fetched upgrade log");
          fetchError = "";
          openWhenReady();
        } else {
          Logger.w("UpdateService", "Failed to fetch upgrade log, status:", request.status);
          releaseContent = "";

          if (request.status === 404) {
            // Changelog not available for this version range - skip silently
            Logger.w("UpdateService", "Changelog not found, skipping display");
            fetchError = "";
            popupScheduled = false;
            markChangelogSeen(toVersion);
          } else {
            // Network error or server issue - show error to user
            fetchError = I18n.tr("changelog.error.fetch-failed");
            openWhenReady();
          }
        }
      }
    };
    request.open("GET", url);
    request.send();
  }

  function normalizeVersion(version) {
    if (!version)
      return "";
    return version.startsWith("v") ? version.substring(1) : version;
  }

  function ensureVersionPrefix(version) {
    if (!version)
      return "";
    return version.startsWith("v") ? version : "v" + version;
  }

  function parseVersionParts(version) {
    const clean = normalizeVersion(version);
    if (!clean)
      return [];
    return clean.split(/[^0-9]+/).filter(part => part.length > 0).map(part => parseInt(part));
  }

  function compareVersions(a, b) {
    if (a === b)
      return 0;
    const partsA = parseVersionParts(a);
    const partsB = parseVersionParts(b);
    const length = Math.max(partsA.length, partsB.length);
    for (var i = 0; i < length; i++) {
      const valA = partsA[i] || 0;
      const valB = partsB[i] || 0;
      if (valA > valB)
        return 1;
      if (valA < valB)
        return -1;
    }
    return 0;
  }

  // Called by shell.qml to show changelog after init
  function checkTelemetryWizardOrChangelog() {
    Logger.d("UpdateService", "checkTelemetryWizardOrChangelog called, stateLoaded:", changelogStateLoaded);
    if (!changelogStateLoaded) {
      Logger.d("UpdateService", "State not loaded yet, setting pending flag");
      pendingShowRequest = true;
      return;
    }

    showLatestChangelog();
  }

  function openWhenReady() {
    if (!popupScheduled)
      return;

    if (!Quickshell.screens || Quickshell.screens.length === 0) {
      return;
    }

    let targetScreen = viewChangelogTargetScreen;

    if (targetScreen) {
      // Explicit screen requested - validate it
      if (!PanelService.canShowPanelsOnScreen(targetScreen)) {
        Logger.w("UpdateService", "Changelog cannot be shown on screen without bar:", targetScreen.name);
        popupScheduled = false;
        viewChangelogTargetScreen = null;
        return;
      }
    } else {
      // No explicit screen - find one that can show panels
      targetScreen = PanelService.findScreenForPanels();
      if (!targetScreen) {
        Logger.w("UpdateService", "No screen available to show changelog");
        popupScheduled = false;
        return;
      }
    }

    const panel = PanelService.getPanel("changelogPanel", targetScreen);
    if (!panel) {
      // Panel not found yet. Wait for popupMenuWindowRegistered signal.
      // This avoids the memory leak (#1306).
      Logger.d("UpdateService", "Waiting for changelogPanel on screen:", targetScreen.name);
      return;
    }

    panel.open();
    popupScheduled = false;
    lastShownVersion = changelogCurrentVersion;
    viewChangelogTargetScreen = null;
  }

  function showLatestChangelog() {
    if (!currentVersion)
      return;

    if (!changelogStateLoaded) {
      pendingShowRequest = true;
      return;
    }

    // Normalize versions for comparison (strip -git, ensure v prefix)
    const lastSeen = ensureVersionPrefix(changelogLastSeenVersion.replace(developmentSuffix, ""));
    const target = ensureVersionPrefix(currentVersion.replace(developmentSuffix, ""));

    if (lastSeen === target)
      return;

    if (!Settings.data.general.showChangelogOnStartup) {
      // user has opted out of seeing changelogs, mark as seen
      markChangelogSeen(target);
      return;
    }

    changelogFromVersion = lastSeen;
    changelogToVersion = target;
    changelogPending = true;
    handleChangelogRequest();
  }

  // Manual changelog viewing (e.g., from Settings > About > View Changelog)
  // Shows all changes since v3.0.0, unlike showLatestChangelog() which uses lastSeenVersion
  property var viewChangelogTargetScreen: null

  function viewChangelog(screen) {
    if (!currentVersion)
      return;

    const target = ensureVersionPrefix(currentVersion.replace(developmentSuffix, ""));
    const fromVersion = "v3.8.2";

    previousVersion = fromVersion;
    changelogCurrentVersion = target;
    viewChangelogTargetScreen = screen || null;
    popupScheduled = true;
    fetchUpgradeLog(fromVersion, target);
  }

  function clearChangelogRequest() {
    changelogPending = false;
    changelogFromVersion = "";
    changelogToVersion = "";
  }

  function markChangelogSeen(version) {
    if (!version)
      return;
    changelogLastSeenVersion = version;
    debouncedSaveChangelogState();
  }

  function loadChangelogState() {
    try {
      const changelog = ShellState.getChangelogState();
      changelogLastSeenVersion = changelog.lastSeenVersion || "";

      // Migration is now handled in Settings.qml
      Logger.d("UpdateService", "Loaded changelog state from ShellState");
    } catch (error) {
      Logger.e("UpdateService", "Failed to load changelog state:", error);
    }
    changelogStateLoaded = true;

    if (pendingShowRequest) {
      pendingShowRequest = false;
      Qt.callLater(root.showLatestChangelog);
    }
  }

  function debouncedSaveChangelogState() {
    // Queue a save and restart the debounce timer
    pendingSave = true;
    saveDebouncer.restart();
  }

  function executeSave() {
    if (!pendingSave)
      return;

    // Prevent concurrent saves
    if (saveInProgress) {
      // Retry after a short delay
      saveDebouncer.start();
      return;
    }

    pendingSave = false;
    saveInProgress = true;

    try {
      ShellState.setChangelogState({
                                     lastSeenVersion: changelogLastSeenVersion || ""
                                   });
      Logger.d("UpdateService", "Saved changelog state to ShellState");
      saveInProgress = false;

      // Check if another save was queued while we were saving
      if (pendingSave) {
        Qt.callLater(executeSave);
      }
    } catch (error) {
      Logger.e("UpdateService", "Failed to save changelog state:", error);
      saveInProgress = false;
    }
  }

  function saveChangelogState() {
    // Immediate save (backward compatibility)
    debouncedSaveChangelogState();
  }
}
