pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI

Singleton {
  id: root

  // Version properties
  property string baseVersion: "3.1.1"
  property bool isDevelopment: true
  property string currentVersion: `v${!isDevelopment ? baseVersion : baseVersion + "-dev"}`

  // Changelog properties
  property bool initialized: false
  property string previousVersion: ""
  property string changelogCurrentVersion: ""
  property var releaseHighlights: []
  property string releaseNotesUrl: ""
  property string discordUrl: "https://discord.noctalia.dev"
  property string lastShownVersion: ""
  property bool popupScheduled: false
  property string feedbackUrl: Quickshell.env("NOCTALIA_CHANGELOG_FEEDBACK_URL") || ""
  property string fetchError: ""

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

    if (Settings.changelogPending) {
      handleChangelogRequest(Settings.changelogFromVersion, Settings.changelogToVersion);
    }
  }

  Connections {
    target: Settings ? Settings : null
    function onChangelogTriggered(fromVersion, toVersion) {
      handleChangelogRequest(fromVersion, toVersion);
    }
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

  function handleChangelogRequest(fromVersion, toVersion) {
    if (!toVersion)
      return;

    if (popupScheduled && changelogCurrentVersion === toVersion)
      return;

    if (!popupScheduled && lastShownVersion === toVersion)
      return;

    previousVersion = fromVersion || "";
    changelogCurrentVersion = toVersion;
    fetchError = GitHubService ? GitHubService.releaseFetchError : "";
    releaseHighlights = buildReleaseHighlights(previousVersion, changelogCurrentVersion);
    releaseNotesUrl = buildReleaseNotesUrl(toVersion);

    popupScheduled = true;
    root.popupQueued(previousVersion, changelogCurrentVersion);

    Settings.clearChangelogRequest();
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
    handleChangelogRequest(Settings.data.changelog.lastSeenVersion, currentVersion);
  }
}
