pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Version service: installed-version detection, upstream GitHub data fetching
// (releases, main commit, contributors), version math, and changelog UX.
Singleton {
  id: root

  // ─────────────────────────────────────────────────────────────
  // Version detection (installed shell version)
  // currentVersion is detected at init (real installed version):
  // VERSION is the tracked release/API identity (packages may add build suffixes).
  // Git only appends HEAD identity in a checkout rooted at the shell directory.
  // Legacy trees without VERSION retain the unknown display fallback below.
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
  readonly property string currentReleaseVersion: releaseVersion(currentVersion)
  // True once versionDetectProcess read VERSION. While false, currentVersion is fallbackVersion, built from
  // baseVersion ("0.1.0") — NOT a real version. Compatibility gates must not
  // compare against it; that is precisely the original "every plugin is
  // incompatible" bug, where baseVersion was the operand too.
  property bool versionKnown: false
  property bool isGitVersion: true
  // True for distributed VERSION-only trees, false for local Git checkouts.
  // The update check only makes sense for packaged installs — dev checkouts
  // manage their own git state and would false-positive when ahead of origin.
  property bool versionFromPackage: false

  // Classify a version string as a -git/dev build (drives the update-check
  // channel: commit-hash comparison for git builds, release tags otherwise)
  function classifyIsGitVersion(v) {
    return /\.r\d+\.g[0-9a-f]+/.test(v) || /-g[0-9a-f]+/.test(v) || v.endsWith("-dirty") || v.endsWith(developmentSuffix);
  }

  // Extract the commit hash from a -git style version (pkgver g<hash> or
  // describe -g<hash>); "" when not a git build
  function versionCommitHash(v) {
    var m = v.match(/\.g([0-9a-f]{7,})/) || v.match(/-g([0-9a-f]{7,})/);
    return m ? m[1] : "";
  }

  Process {
    id: versionDetectProcess
    // Pass the directory as argv: quotes/spaces in worktree paths are data.
    // .git can be a directory or a linked-worktree file. Never inherit a parent
    // checkout's HEAD, and never discard VERSION because Git is unavailable.
    command: ["sh", "-c",
      'root=$(cd "$1" && pwd -P) || exit; [ -f "$root/VERSION" ] || exit; provenance=pkg; hash=; if [ -e "$root/.git" ]; then provenance=git; top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null); if [ "$top" = "$root" ]; then hash=$(git -C "$root" rev-parse --short=9 HEAD 2>/dev/null) || hash=; fi; fi; printf "%s\\n%s\\n%s\\n" "$provenance" "$(cat "$root/VERSION")" "$hash"',
      "version-detect", Quickshell.shellDir]
    running: false

    onExited: function (exitCode) {
      var lines = stdout.text.trim().split("\n");
      var fromPackage = lines[0] === "pkg";
      var detected = (lines[1] || "").trim();
      if (detected !== "") {
        // Strip pacman pkgrel suffix ("...-1") from packaged versions
        var stripped = detected.replace(/-\d+$/, "");
        const hash = (lines[2] || "").trim();
        if (/^[0-9a-f]{7,}$/.test(hash) && !root.classifyIsGitVersion(stripped))
          stripped += "-g" + hash;
        root.currentVersion = stripped;
        root.versionKnown = true;
        root.isGitVersion = root.classifyIsGitVersion(stripped);
        root.versionFromPackage = fromPackage;
        Logger.i("Version", "Detected installed version:", stripped, "(git:", root.isGitVersion + ", packaged:", root.versionFromPackage + ")");
        root.resumeChangelogRequests();
      } else {
        Logger.i("Version", "No VERSION file — using fallback version:", root.currentVersion);
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // ─────────────────────────────────────────────────────────────
  // GitHub data (latest release, latest QS release, main commit, contributors)
  property string githubDataFile: Quickshell.env("ATMOSPHERA_GITHUB_FILE") || (Settings.cacheDir + "github.json")
  property int githubUpdateFrequency: 60 * 60 // 1 hour expressed in seconds
  property bool isFetchingData: false
  readonly property alias data: adapter // Used to access via Version.data.xxx.yyy

  // Public properties for easy access
  property string latestVersion: I18n.tr("common.unknown")
  property string latestQSVersion: I18n.tr("common.unknown")
  property string latestMainCommit: ""
  property var contributors: []

  property bool isInitialized: false

  FileView {
    id: githubDataFileView
    path: githubDataFile
    printErrors: false
    watchChanges: false  // Disable to prevent reload on our own writes
    Component.onCompleted: {
      // Data loading handled by FileView onLoaded
    }
    onLoaded: {
      if (!root.isInitialized) {
        root.isInitialized = true;
        loadFromCache();
      }
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        // No cache file exists, fetch fresh data
        root.isInitialized = true;
        fetchFromGitHub();
      }
    }

    JsonAdapter {
      id: adapter

      property string version: I18n.tr("common.unknown")
      property string qsVersion: I18n.tr("common.unknown")
      property var contributors: []
      property real timestamp: 0
    }
  }

  function loadFromCache() {
    const now = Time.timestamp;
    var needsRefetch = false;

    Logger.i("GitHub", "Checking cache - timestamp:", data.timestamp, "now:", now, "age:", data.timestamp ? Math.round((now - data.timestamp) / 60) : "N/A", "minutes");

    if (!data.timestamp || (now >= data.timestamp + githubUpdateFrequency)) {
      needsRefetch = true;
      Logger.i("GitHub", "Cache expired or missing, scheduling fetch (update frequency:", Math.round(githubUpdateFrequency / 60), "minutes)");
    } else {
      Logger.i("GitHub", "Cache is fresh, using cached data (age:", Math.round((now - data.timestamp) / 60) + " minutes)");
    }

    if (data.version) {
      root.latestVersion = data.version;
    }
    if (data.qsVersion) {
      root.latestQSVersion = data.qsVersion;
    }
    if (data.contributors && data.contributors.length > 0) {
      root.contributors = data.contributors;
      Logger.d("GitHub", "Loaded", data.contributors.length, "contributors from cache");
    }

    if (needsRefetch) {
      fetchFromGitHub();
    }
  }

  function fetchFromGitHub() {
    if (isFetchingData) {
      Logger.d("GitHub", "GitHub data is still fetching");
      return;
    }

    isFetchingData = true;
    versionProcess.running = true;
    qsVersionProcess.running = true;
    contributorsProcess.running = true;
    mainCommitProcess.running = true;
  }

  // Latest main-branch commit of our repo — drives the -git update check
  Process {
    id: mainCommitProcess

    command: ["curl", "-s", "https://api.github.com/repos/atmosphera-dev/atmosphera/commits/main"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          if (response && response.trim()) {
            const data = JSON.parse(response);
            if (data.sha) {
              root.latestMainCommit = data.sha;
              Logger.d("GitHub", "Latest main commit fetched:", data.sha.substring(0, 9));
            } else if (data.message) {
              Logger.w("GitHub", "Main commit API error:", data.message);
            }
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse main commit response:", e);
        }
      }
    }
  }

  function saveData() {
    data.timestamp = Time.timestamp;
    Logger.d("GitHub", "Saving data to cache file:", githubDataFile, "with timestamp:", data.timestamp);
    Logger.d("GitHub", "Data to save - version:", data.version, "qsVersion:", data.qsVersion, "contributors:", data.contributors.length);

    // Ensure cache directory exists
    Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir]);

    try {
      // Write immediately instead of Qt.callLater to ensure it completes
      githubDataFileView.writeAdapter();
      Logger.d("GitHub", "Cache file written successfully");
    } catch (error) {
      Logger.e("GitHub", "Failed to write cache file:", error);
    }
  }

  function checkAndSaveData() {
    // Only save when all processes are finished
    if (!versionProcess.running && !qsVersionProcess.running && !contributorsProcess.running) {
      root.isFetchingData = false;

      // Check results
      var anySucceeded = versionProcess.fetchSucceeded || qsVersionProcess.fetchSucceeded || contributorsProcess.fetchSucceeded;
      var wasRateLimited = versionProcess.wasRateLimited || qsVersionProcess.wasRateLimited || contributorsProcess.wasRateLimited;

      if (anySucceeded) {
        root.saveData();
        Logger.d("GitHub", "Successfully fetched data from GitHub");
      } else if (wasRateLimited) {
        root.saveData();
        Logger.w("GitHub", "API rate limited - using cached data (retry in", Math.round(githubUpdateFrequency / 60), "minutes)");
      } else {
        Logger.w("GitHub", "API request failed - using cached data without updating timestamp");
      }

      // Reset fetch flags for next time
      versionProcess.fetchSucceeded = false;
      versionProcess.wasRateLimited = false;
      qsVersionProcess.fetchSucceeded = false;
      qsVersionProcess.wasRateLimited = false;
      contributorsProcess.fetchSucceeded = false;
      contributorsProcess.wasRateLimited = false;
    }
  }

  function resetCache() {
    data.version = I18n.tr("common.unknown");
    data.qsVersion = I18n.tr("common.unknown");
    data.contributors = [];
    data.timestamp = 0;

    // Try to fetch immediately
    fetchFromGitHub();
  }

  Process {
    id: versionProcess

    property bool fetchSucceeded: false
    property bool wasRateLimited: false

    command: ["curl", "-s", "https://api.github.com/repos/atmosphera-dev/atmosphera/releases/latest"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          if (response && response.trim()) {
            const data = JSON.parse(response);
            if (data.tag_name) {
              const version = data.tag_name;
              root.data.version = version;
              root.latestVersion = version;
              versionProcess.fetchSucceeded = true;
              Logger.d("GitHub", "Latest version fetched:", version);
            } else if (data.message) {
              // Check if it's a rate limit error
              if (data.message.includes("rate limit")) {
                versionProcess.wasRateLimited = true;
              } else {
                Logger.w("GitHub", "Version API error:", data.message);
              }
            }
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse version response:", e);
        }

        // Check if all processes are done
        checkAndSaveData();
      }
    }
  }

  Process {
    id: qsVersionProcess

    property bool fetchSucceeded: false
    property bool wasRateLimited: false

    command: ["curl", "-s", "https://api.github.com/repos/quickshell-mirror/quickshell/releases/latest"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          if (response && response.trim()) {
            const data = JSON.parse(response);
            if (data.tag_name) {
              const version = data.tag_name;
              root.data.qsVersion = version;
              root.latestQSVersion = version;
              qsVersionProcess.fetchSucceeded = true;
              Logger.d("GitHub", "Latest QS version fetched:", version);
            } else if (data.message) {
              // Check if it's a rate limit error
              if (data.message.includes("rate limit")) {
                qsVersionProcess.wasRateLimited = true;
              } else {
                Logger.w("GitHub", "QS Version API error:", data.message);
              }
            }
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse QS version response:", e);
        }

        // Check if all processes are done
        checkAndSaveData();
      }
    }
  }

  Process {
    id: contributorsProcess

    property bool fetchSucceeded: false
    property bool wasRateLimited: false

    command: ["curl", "-s", "https://api.github.com/repos/noctalia-dev/noctalia-shell/contributors?per_page=100"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const response = text;
          Logger.d("GitHub", "Raw contributors response length:", response ? response.length : 0);
          if (response && response.trim()) {
            const data = JSON.parse(response);
            Logger.d("GitHub", "Parsed contributors data type:", typeof data, "length:", Array.isArray(data) ? data.length : "not array");
            // Only update if we got a valid array
            if (Array.isArray(data)) {
              root.data.contributors = data;
              root.contributors = root.data.contributors;
              contributorsProcess.fetchSucceeded = true;
              Logger.d("GitHub", "Contributors fetched:", root.contributors.length);
            } else if (data.message) {
              // Check if it's a rate limit error
              if (data.message.includes("rate limit")) {
                contributorsProcess.wasRateLimited = true;
              } else {
                Logger.w("GitHub", "Contributors API error:", data.message);
              }
            }
          }
        } catch (e) {
          Logger.e("GitHub", "Failed to parse contributors response:", e);
        }

        // Check if all processes are done
        checkAndSaveData();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Changelog ownership: bundled release sections, eligibility and acknowledgment.
  // UI surfaces only request notes or forward dismissal; build hashes never
  // participate in release selection or the durable seen marker.

  // Changelog properties
  property bool initialized: false
  // The bundled notes; relative images in them resolve against this file.
  readonly property string changelogPath: Quickshell.shellPath("CHANGELOG.md")
  property string previousVersion: ""
  property string changelogCurrentVersion: ""
  property var changelogSections: []
  property bool changelogNotesLoaded: false
  readonly property string releaseContent: versionKnown ? notesForRange(previousVersion, currentReleaseVersion) : ""
  property string lastShownVersion: ""
  property bool popupScheduled: false
  property string changelogLastSeenVersion: ""
  property bool changelogStateLoaded: false
  property bool pendingShowRequest: false
  property bool pendingViewRequest: false
  property var viewChangelogTargetScreen: null

  // Fix for FileView race condition
  property bool saveInProgress: false
  property bool pendingSave: false

  FileView {
    path: root.changelogPath
    printErrors: false
    watchChanges: false
    onLoaded: {
      root.changelogSections = root.parseChangelog(text());
      root.changelogNotesLoaded = true;
      root.resumeChangelogRequests();
    }
    onLoadFailed: {
      root.changelogSections = [];
      root.changelogNotesLoaded = true;
      root.resumeChangelogRequests();
    }
  }

  // Preserve each complete release section, excluding headings without notes.
  // Unreleased/future entries and dated subheadings are not release identities.
  function parseChangelog(markdown) {
    const headings = /^##\s+\[v?(\d+\.\d+\.\d+)\][^\n]*$/gm;
    const sections = [];
    let previous = null;
    let match;
    while ((match = headings.exec(markdown)) !== null) {
      if (previous && markdown.slice(previous.body, match.index).trim())
        sections.push({
                        version: previous.version,
                        content: markdown.slice(previous.start, match.index).trim()
                      });
      previous = {
        version: match[1],
        start: match.index,
        body: headings.lastIndex
      };
    }
    if (previous && markdown.slice(previous.body).trim())
      sections.push({
                      version: previous.version,
                      content: markdown.slice(previous.start).trim()
                    });
    return sections.sort((a, b) => compareVersions(b.version, a.version));
  }

  function notesForRange(fromVersion, toVersion) {
    if (!toVersion)
      return "";
    return changelogSections.filter(section => compareVersions(section.version, toVersion) <= 0 && (!fromVersion || compareVersions(section.version, fromVersion) > 0)).map(section => section.content).join("\n\n");
  }

  function resumeChangelogRequests() {
    if (!versionKnown || !changelogNotesLoaded)
      return;
    if (pendingViewRequest) {
      pendingViewRequest = false;
      viewChangelog(viewChangelogTargetScreen);
    } else if (pendingShowRequest && changelogStateLoaded) {
      pendingShowRequest = false;
      showLatestChangelog();
    }
  }

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
    Logger.i("GitHub", "Service started");

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
    const clean = releaseVersion(version);
    if (!clean)
      return [];
    return clean.split(".").map(part => parseInt(part));
  }

  // One release identity for API comparisons and changelog consumers. Build
  // counts/hashes/pkgrel are never additional numeric version components.
  // Major/minor-only requirements remain meaningful for the Noctalia banner.
  function releaseVersion(version) {
    const match = normalizeVersion(version).match(/^(\d+(?:\.\d+){0,2})(?=$|[.-])/);
    return match ? match[1] : "";
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
  function checkChangelogPrompt() {
    pendingShowRequest = true;
    resumeChangelogRequests();
  }

  function openWhenReady() {
    if (!popupScheduled || !releaseContent.trim())
      return;

    if (!Quickshell.screens || Quickshell.screens.length === 0) {
      return;
    }

    let targetScreen = viewChangelogTargetScreen;

    if (targetScreen) {
      // Explicit screen requested - validate it
      if (!PanelService.canShowPanelsOnScreen(targetScreen)) {
        Logger.w("Version", "Changelog cannot be shown on screen without bar:", targetScreen.name);
        popupScheduled = false;
        viewChangelogTargetScreen = null;
        return;
      }
    } else {
      // No explicit screen - find one that can show panels
      targetScreen = PanelService.findScreenForPanels();
      if (!targetScreen) {
        Logger.w("Version", "No screen available to show changelog");
        popupScheduled = false;
        return;
      }
    }

    const panel = PanelService.getPanel("changelogPanel", targetScreen);
    if (!panel) {
      // Panel not found yet. Wait for popupMenuWindowRegistered signal.
      // This avoids the memory leak (#1306).
      Logger.d("Version", "Waiting for changelogPanel on screen:", targetScreen.name);
      return;
    }

    panel.open();
    popupScheduled = false;
    lastShownVersion = changelogCurrentVersion;
    viewChangelogTargetScreen = null;
  }

  function showLatestChangelog() {
    if (!versionKnown || !changelogStateLoaded || !changelogNotesLoaded) {
      pendingShowRequest = true;
      return;
    }

    const lastSeen = ensureVersionPrefix(releaseVersion(changelogLastSeenVersion));
    const target = ensureVersionPrefix(currentReleaseVersion);

    // Packaged -git builds are releases for this UX; source checkouts are not.
    if (!target || !versionFromPackage || Settings.shouldOpenSetupWizard || !Settings.data.general.showChangelogOnStartup)
      return;
    if (lastSeen && compareVersions(lastSeen, target) >= 0)
      return;
    if (lastShownVersion === target || popupScheduled || !notesForRange(lastSeen, target).trim())
      return;
    previousVersion = lastSeen;
    changelogCurrentVersion = target;
    popupScheduled = true;
    root.popupQueued(previousVersion, target);
    openWhenReady();
  }

  // About and the manual dialog use all bundled sections up to this release,
  // independent of acknowledgment and checkout/package provenance.
  function loadChangelog() {
    previousVersion = "";
    changelogCurrentVersion = versionKnown ? ensureVersionPrefix(currentReleaseVersion) : "";
  }

  function viewChangelog(screen) {
    viewChangelogTargetScreen = screen || null;
    pendingShowRequest = false;
    if (!versionKnown || !changelogNotesLoaded) {
      pendingViewRequest = true;
      return;
    }
    loadChangelog();
    popupScheduled = releaseContent.trim() !== "";
    openWhenReady();
  }

  function dismissChangelog() {
    if (releaseContent.trim())
      markChangelogSeen(changelogCurrentVersion);
  }

  function markChangelogSeen(version) {
    const release = ensureVersionPrefix(releaseVersion(version));
    if (!release || (changelogLastSeenVersion && compareVersions(release, changelogLastSeenVersion) < 0))
      return;
    changelogLastSeenVersion = release;
    debouncedSaveChangelogState();
  }

  function loadChangelogState() {
    try {
      const changelog = ShellState.getChangelogState();
      changelogLastSeenVersion = ensureVersionPrefix(releaseVersion(changelog.lastSeenVersion || ""));

      // Migration is now handled in Settings.qml
      Logger.d("Version", "Loaded changelog state from ShellState");
    } catch (error) {
      Logger.e("Version", "Failed to load changelog state:", error);
    }
    changelogStateLoaded = true;

    resumeChangelogRequests();
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
      Logger.d("Version", "Saved changelog state to ShellState");
      saveInProgress = false;

      // Check if another save was queued while we were saving
      if (pendingSave) {
        Qt.callLater(executeSave);
      }
    } catch (error) {
      Logger.e("Version", "Failed to save changelog state:", error);
      saveInProgress = false;
    }
  }

  function saveChangelogState() {
    // Immediate save (backward compatibility)
    debouncedSaveChangelogState();
  }
}
