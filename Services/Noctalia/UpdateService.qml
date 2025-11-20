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
  property string baseVersion: "3.2.0"
  property bool isDevelopment: true
  property string currentVersion: `v${!isDevelopment ? baseVersion : baseVersion + "-dev"}`
  property string changelogStateFile: Quickshell.env("NOCTALIA_CHANGELOG_STATE_FILE") || (Settings.cacheDir + "changelog-state.json")

  // Changelog properties
  property bool initialized: false
  property bool changelogPending: false
  property string changelogFromVersion: ""
  property string changelogToVersion: ""
  property string previousVersion: ""
  property string changelogCurrentVersion: ""
  property var releaseHighlights: []
  property string releaseNotesUrl: ""
  property string discordUrl: "https://discord.noctalia.dev"
  property string lastShownVersion: ""
  property bool popupScheduled: false
  property string feedbackUrl: Quickshell.env("NOCTALIA_CHANGELOG_FEEDBACK_URL") || ""
  property string fetchError: ""
  property string changelogLastSeenVersion: ""
  property bool changelogStateLoaded: false
  property bool pendingShowRequest: false
  
  // Fix for FileView race condition
  property bool saveInProgress: false
  property bool pendingSave: false
  property int saveDebounceTimer: 0

  signal popupQueued(string fromVersion, string toVersion)

  // Internal helpers
  function getVersion() {
    return root.currentVersion;
  }

  function checkForUpdates() {
    // TODO: Implement update checking logic
    Logger.i("UpdateService", "Checking for updates...");
  }

  function init() {
    if (initialized)
      return;

    initialized = true;
    Logger.i("UpdateService", "Version:", root.currentVersion);
  }

  Connections {
    target: GitHubService ? GitHubService : null
    function onReleaseNotesChanged() {
      rebuildHighlights();
    }
    function onReleasesChanged() {
      rebuildHighlights();
    }
    function onReleaseFetchErrorChanged() {
      fetchError = GitHubService ? GitHubService.releaseFetchError : "";
    }
  }

  FileView {
    id: changelogStateFileView
    path: root.changelogStateFile
    printErrors: false
    onLoaded: loadChangelogState()
    onLoadFailed: error => {
      if (error === 2) {
        // File doesn't exist, create it
        debouncedSaveChangelogState();
      } else {
        Logger.e("UpdateService", "Failed to load changelog state file:", error);
      }
      changelogStateLoaded = true;
      if (pendingShowRequest) {
        pendingShowRequest = false;
        Qt.callLater(root.showLatestChangelog);
      }
    }

    JsonAdapter {
      id: changelogStateAdapter
      property string lastSeenVersion: ""
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
    
    if (!toVersion)
      return;

    if (popupScheduled && changelogCurrentVersion === toVersion)
      return;

    if (!popupScheduled && lastShownVersion === toVersion)
      return;

    previousVersion = fromVersion;
    changelogCurrentVersion = toVersion;
    fetchError = GitHubService ? GitHubService.releaseFetchError : "";
    releaseHighlights = buildReleaseHighlights(previousVersion, changelogCurrentVersion);
    releaseNotesUrl = buildReleaseNotesUrl(toVersion);

    popupScheduled = true;
    root.popupQueued(previousVersion, changelogCurrentVersion);

    clearChangelogRequest();
    openWhenReady();
  }

  function rebuildHighlights() {
    if (!changelogCurrentVersion)
      return;
    fetchError = GitHubService ? GitHubService.releaseFetchError : "";
    releaseHighlights = buildReleaseHighlights(previousVersion, changelogCurrentVersion);
  }

  function buildReleaseHighlights(fromVersion, toVersion) {
    const releases = GitHubService && GitHubService.releases ? GitHubService.releases : [];
    const selected = [];
    const fromNorm = normalizeVersion(fromVersion);
    const toNorm = normalizeVersion(toVersion);

    if (releases.length > 0) {
      for (var i = 0; i < releases.length; i++) {
        const rel = releases[i];
        const tag = rel.version || "";
        const tagNorm = normalizeVersion(tag);
        if (!tagNorm)
          continue;

        if (toNorm && compareVersions(tagNorm, toNorm) > 0) {
          continue;
        }

        if (fromNorm && compareVersions(tagNorm, fromNorm) <= 0) {
          break;
        }

        const entries = parseReleaseNotes(rel.body);
        if (entries.length === 0)
          continue;

        selected.push({
          "version": tag,
          "date": rel.createdAt || "",
          "entries": entries
        });
      }
    }

    if (selected.length === 0 && toVersion) {
      const fallback = parseReleaseNotes(GitHubService ? GitHubService.releaseNotes : "");
      if (fallback.length > 0) {
        selected.push({
          "version": toVersion,
          "date": "",
          "entries": fallback
        });
        fetchError = "";
      }
    }

    return selected;
  }

  function normalizeVersion(version) {
    if (!version)
      return "";
    return version.startsWith("v") ? version.substring(1) : version;
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

  function buildReleaseNotesUrl(version) {
    if (!version)
      return "";
    const tag = version.startsWith("v") ? version : `v${version}`;
    return `https://github.com/noctalia-dev/noctalia-shell/releases/tag/${tag}`;
  }

  function parseReleaseNotes(body) {
    if (!body)
      return [];

    const lines = body.split(/\r?\n/);
    var entries = [];

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line)
        continue;

      if (line.startsWith("- ") || line.startsWith("* ")) {
        const text = cleanEntry(line.substring(2).trim());
        if (text.length > 0 && !isVersionLine(text) && !isIgnoredEntry(text)) {
          entries.push(text);
        }
      }

      if (entries.length >= 6)
        break;
    }

    var uniqueEntries = [];
    var seen = {};
    for (var j = 0; j < entries.length; j++) {
      const key = entries[j].toLowerCase();
      if (seen[key])
        continue;
      seen[key] = true;
      uniqueEntries.push(entries[j]);
    }

    return uniqueEntries;
  }

  function isVersionLine(text) {
    return /^v?\d/i.test(text);
  }

  function cleanEntry(text) {
    if (!text)
      return "";

    var cleaned = text;

    // Strip markdown links [label](url)
    cleaned = cleaned.replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1").trim();

    // Drop bare URLs or parentheses wrapping URLs
    cleaned = cleaned.replace(/\((https?:\/\/[^)]+)\)/gi, "").trim();

    cleaned = cleaned.replace(/\([0-9a-f]{7,}\)/gi, "").trim();
    cleaned = cleaned.replace(/\s+by\s+[A-Za-z0-9_-]+$/i, "").trim();
    cleaned = cleaned.replace(/\s{2,}/g, " ");

    if (cleaned.toLowerCase().startsWith("merge branch")) {
      const ofIndex = cleaned.indexOf(" of ");
      if (ofIndex > -1) {
        cleaned = cleaned.substring(0, ofIndex).trim();
      }
    }

    return cleaned;
  }

  function isIgnoredEntry(text) {
    const lower = text.toLowerCase();
    if (lower.startsWith("release v"))
      return true;
    if (lower.includes("autoformat") || lower.includes("auto-formatting"))
      return true;
    if (lower.includes("qmlfmt"))
      return true;
    return false;
  }

  function openWhenReady() {
    if (!popupScheduled)
      return;

    if (!Quickshell.screens || Quickshell.screens.length === 0) {
      Qt.callLater(openWhenReady);
      return;
    }

    const targetScreen = Quickshell.screens[0];
    const panel = PanelService.getPanel("changelogPanel", targetScreen);
    if (!panel) {
      Qt.callLater(openWhenReady);
      return;
    }

    panel.open();
    popupScheduled = false;
    lastShownVersion = changelogCurrentVersion;
  }

  function openReleaseNotes() {
    if (!releaseNotesUrl)
      return;
    Quickshell.execDetached(["xdg-open", releaseNotesUrl]);
  }

  function openDiscord() {
    if (!discordUrl)
      return;
    Quickshell.execDetached(["xdg-open", discordUrl]);
  }

  function openFeedbackForm() {
    if (!feedbackUrl)
      return;
    Quickshell.execDetached(["xdg-open", feedbackUrl]);
  }

  function showLatestChangelog() {
    if (!currentVersion)
      return;

    if (!changelogStateLoaded) {
      pendingShowRequest = true;
      return;
    }

    const lastSeen = changelogLastSeenVersion || "";
    if (lastSeen === currentVersion)
      return;

    changelogFromVersion = lastSeen;
    changelogToVersion = currentVersion;
    changelogPending = true;
    handleChangelogRequest();
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
      changelogLastSeenVersion = changelogStateAdapter.lastSeenVersion || "";
      if (!changelogLastSeenVersion && Settings.data && Settings.data.changelog && Settings.data.changelog.lastSeenVersion) {
        changelogLastSeenVersion = Settings.data.changelog.lastSeenVersion;
        debouncedSaveChangelogState();
        Logger.i("UpdateService", "Migrated changelog lastSeenVersion from settings to cache");
      }
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
      changelogStateAdapter.lastSeenVersion = changelogLastSeenVersion || "";
      
      // Ensure cache directory exists
      Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir]);
      
      // Small delay to ensure directory creation completes
      Qt.callLater(() => {
        try {
          changelogStateFileView.writeAdapter();
          saveInProgress = false;
          
          // Check if another save was queued while we were saving
          if (pendingSave) {
            Qt.callLater(executeSave);
          }
        } catch (writeError) {
          Logger.e("UpdateService", "Failed to write changelog state:", writeError);
          saveInProgress = false;
        }
      });
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