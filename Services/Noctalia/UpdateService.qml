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

  // Changelog fetching
  property string changelogBaseUrl: Quickshell.env("NOCTALIA_CHANGELOG_URL") || "https://noctalia.dev:7777/changelogs"
  property int changelogFetchLimit: 25
  property int changelogUpdateFrequency: 60 * 60 // 1 hour in seconds
  property bool isFetchingChangelogs: false
  property string releaseNotes: ""
  property var releases: []
  property string changelogDataFile: Quickshell.env("NOCTALIA_CHANGELOG_FILE") || (Settings.cacheDir + "changelogs.json")

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

  // Watch for changes to trigger highlight rebuilds
  onReleasesChanged: {
    rebuildHighlights();
  }

  onReleaseNotesChanged: {
    rebuildHighlights();
  }

  // Changelog data cache
  FileView {
    id: changelogDataFileView
    path: root.changelogDataFile
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    Component.onCompleted: {
      reload();
    }
    onLoaded: {
      loadChangelogCache();
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        Qt.callLater(() => {
                       fetchChangelogs();
                     });
      }
    }

    JsonAdapter {
      id: changelogAdapter

      property string releaseNotes: ""
      property var releases: []
      property real timestamp: 0
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
    releaseHighlights = buildReleaseHighlights(previousVersion, changelogCurrentVersion);
  }

  function buildReleaseHighlights(fromVersion, toVersion) {
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
      const fallback = parseReleaseNotes(releaseNotes);
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
    return `${changelogBaseUrl}/CHANGELOG-${tag}.txt`;
  }

function parseReleaseNotes(body) {
    if (!body)
      return [];

    const lines = body.split(/\r?\n/);
    var entries = [];

    for (var i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();

      if (trimmed.match(/^Release\s+v[0-9]/i)) {
        continue;
      }

      if (trimmed.match(/^##\s*Changes since/i)) {
        break;
      }

      // If this line is just an emoji and the next line has text, merge them
      if (trimmed.match(/^[\u{1F000}-\u{1F9FF}]$/u) && i + 1 < lines.length) {
        const nextLine = lines[i + 1].trim();
        if (nextLine.length > 0) {
          entries.push(trimmed + " " + nextLine);
          i++; // Skip the next line since we merged it
          continue;
        }
      }

      entries.push(line);
    }

    // Remove trailing blank lines
    while (entries.length > 0 && entries[entries.length - 1].trim().length === 0) {
      entries.pop();
    }

    return entries;
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

  // Changelog fetching functions

  function loadChangelogCache() {
    const now = Time.timestamp;
    var needsRefetch = false;
    if (!changelogAdapter.timestamp || (now >= changelogAdapter.timestamp + changelogUpdateFrequency)) {
      needsRefetch = true;
      Logger.d("UpdateService", "Changelog cache expired or missing, scheduling fetch");
    } else {
      Logger.d("UpdateService", "Loading cached changelog data (age:", Math.round((now - changelogAdapter.timestamp) / 60), "minutes)");
    }

    if (changelogAdapter.releaseNotes) {
      root.releaseNotes = changelogAdapter.releaseNotes;
    }
    if (changelogAdapter.releases && changelogAdapter.releases.length > 0) {
      root.releases = changelogAdapter.releases;
    } else {
      Logger.d("UpdateService", "Cached releases missing, scheduling fetch");
      needsRefetch = true;
    }

    if (needsRefetch) {
      fetchChangelogs();
    }
  }

  function fetchChangelogs() {
    if (isFetchingChangelogs) {
      Logger.w("UpdateService", "Changelog data is still fetching");
      return;
    }

    isFetchingChangelogs = true;
    fetchError = "";
    fetchChangelogIndex();
  }

  function fetchChangelogIndex() {
    const request = new XMLHttpRequest();
    request.onreadystatechange = function () {
      if (request.readyState === XMLHttpRequest.DONE) {
        if (request.status >= 200 && request.status < 300) {
          const entries = parseChangelogIndex(request.responseText || "");
          if (entries.length === 0) {
            Logger.w("UpdateService", "No changelog entries found at", changelogBaseUrl);
            fetchError = I18n.tr("changelog.error.fetch-failed");
            finalizeChangelogFetch([]);
          } else {
            fetchChangelogFiles(entries, 0, []);
          }
        } else {
          Logger.e("UpdateService", "Failed to fetch changelog index:", request.status, request.responseText);
          fetchError = I18n.tr("changelog.error.fetch-failed");
          finalizeChangelogFetch([]);
        }
      }
    };
    request.open("GET", changelogBaseUrl);
    request.send();
  }

  function parseChangelogIndex(content) {
    if (!content)
      return [];

    const lines = content.split(/\r?\n/);
    var entries = [];
    for (var i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      const match = trimmed.match(/CHANGELOG-(v[0-9A-Za-z.\-]+)\.txt/);
      if (match && match.length >= 2) {
        const version = match[1];
        const fileName = match[0];
        var modified = "";
        for (var j = i + 1; j < Math.min(lines.length, i + 4); j++) {
          const modLine = lines[j].trim();
          const modMatch = modLine.match(/^Last modified:\s*(.+)$/i);
          if (modMatch && modMatch.length >= 2) {
            modified = modMatch[1].trim();
            break;
          }
        }

        entries.push({
                      "version": version,
                      "fileName": fileName,
                      "url": `${changelogBaseUrl}/${fileName}`,
                      "createdAt": modified
                    });
      }
    }

    entries.sort(function (a, b) {
      return compareVersions(b.version, a.version);
    });

    if (entries.length > changelogFetchLimit) {
      entries = entries.slice(0, changelogFetchLimit);
    }

    return entries;
  }

  function fetchChangelogFiles(entries, index, accumulator) {
    if (!entries || entries.length === 0) {
      finalizeChangelogFetch([]);
      return;
    }

    if (index >= entries.length) {
      finalizeChangelogFetch(accumulator);
      return;
    }

    const entry = entries[index];
    const request = new XMLHttpRequest();
    request.onreadystatechange = function () {
      if (request.readyState === XMLHttpRequest.DONE) {
        if (request.status >= 200 && request.status < 300) {
          accumulator.push({
                            "version": entry.version,
                            "createdAt": entry.createdAt || "",
                            "body": request.responseText || ""
                          });
        } else {
          Logger.e("UpdateService", "Failed to fetch changelog file:", entry.url, "status:", request.status);
          if (!fetchError) {
            fetchError = I18n.tr("changelog.error.fetch-failed");
          }
        }
        fetchChangelogFiles(entries, index + 1, accumulator);
      }
    };
    request.open("GET", entry.url);
    request.send();
  }

  function finalizeChangelogFetch(releasesList) {
    isFetchingChangelogs = false;

    if (releasesList && releasesList.length > 0) {
      releasesList.sort(function (a, b) {
        return compareVersions(b.version, a.version);
      });

      changelogAdapter.releases = releasesList;
      root.releases = releasesList;
      const latest = releasesList[0];
      if (latest) {
        changelogAdapter.releaseNotes = latest.body || "";
        root.releaseNotes = changelogAdapter.releaseNotes;
      }

      if (!fetchError) {
        Logger.d("UpdateService", "Fetched changelog entries:", releasesList.length);
      }
    } else {
      changelogAdapter.releases = [];
      root.releases = [];
      if (!fetchError) {
        Logger.w("UpdateService", "No changelog entries fetched");
        fetchError = I18n.tr("changelog.error.fetch-failed");
      }
    }

    saveChangelogData();
  }

  function saveChangelogData() {
    changelogAdapter.timestamp = Time.timestamp;
    Logger.d("UpdateService", "Saving changelog data to cache file:", changelogDataFile);

    // Ensure cache directory exists
    Quickshell.execDetached(["mkdir", "-p", Settings.cacheDir]);

    Qt.callLater(() => {
                   changelogDataFileView.writeAdapter();
                   Logger.d("UpdateService", "Changelog cache file written successfully");
                 });
  }

  function resetChangelogCache() {
    changelogAdapter.version = I18n.tr("system.unknown-version");
    changelogAdapter.releaseNotes = "";
    changelogAdapter.releases = [];
    changelogAdapter.timestamp = 0;

    fetchChangelogs();
  }

  function clearReleaseCache() {
    Logger.d("UpdateService", "Clearing cached release data");
    changelogAdapter.releases = [];
    root.releases = [];
    changelogDataFileView.writeAdapter();
  }
}
