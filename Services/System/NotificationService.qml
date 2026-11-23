pragma Singleton

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../../Helpers/PortalPaths.js" as PortalPaths
import "../../Helpers/sha256.js" as Checksum
import qs.Commons
import qs.Services.Compositor
import qs.Services.Media
import qs.Services.Power
import qs.Services.System
import qs.Services.UI

Singleton {
  id: root

  // Configuration
  property int maxPopups: 5
  property int maxHistory: 100
  property string historyFile: Quickshell.env("ATMOSPHERA_NOTIF_HISTORY_FILE") || (Settings.cacheDir + "notifications.json")

  // State
  property real lastSeenTs: 0
  // Volatile property that doesn't persist to settings (similar to atmospheraPerformanceMode)
  property bool doNotDisturb: false

  // Models
  property ListModel popupModel: ListModel {}
  property ListModel historyModel: ListModel {}

  // Internal state
  // One entry owns both deferred model memberships and its immutable image
  // revision. The producer object is mutable and is never the image snapshot.
  property var popupState: ({})
  property var quickshellIdToInternalId: ({})
  property int admissionSerial: 0

  // Rate limiting for notification sounds (minimum 100ms between sounds)
  property var lastSoundTime: 0
  readonly property int minSoundInterval: 100

  // Notification server
  property var notificationServerLoader: null

  Component {
    id: notificationServerComponent
    NotificationServer {
      keepOnReload: false
      imageSupported: true
      actionsSupported: true
      onNotification: notification => handleNotification(notification)
    }
  }

  Component {
    id: notificationWatcherComponent
    Connections {
      property var targetNotification
      property var targetDataId
      target: targetNotification
      // Capture in the signal stack; a dirty QML binding can be reevaluated
      // only after the provider's borrowed pixels have changed or retired.
      function onSummaryChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onBodyChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onAppNameChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onDesktopEntryChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onUrgencyChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onExpireTimeoutChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onAppIconChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onImageChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onActionsChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onTransientChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onResidentChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onHasActionIconsChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onHasInlineReplyChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onInlineReplyPlaceholderChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
      function onHintsChanged() {
        root.updateNotificationFromObject(targetDataId);
      }
    }
  }

  function updateNotificationServer() {
    const enabled = Settings.isLoaded && ImageCacheService.admissionReady && Settings.data.notifications.enabled !== false;
    if (enabled === Boolean(notificationServerLoader))
      return;

    if (notificationServerLoader) {
      notificationServerLoader.destroy();
      notificationServerLoader = null;
    }

    if (enabled) {
      notificationServerLoader = notificationServerComponent.createObject(root);
    }
  }

  Component.onCompleted: {
    if (Settings.isLoaded) {
      updateNotificationServer();
    }

    // Load state from ShellState
    Qt.callLater(() => {
      if (typeof ShellState !== 'undefined' && ShellState.isLoaded) {
        loadState();
      }
    });
  }

  Connections {
    target: typeof ShellState !== 'undefined' ? ShellState : null
    function onIsLoadedChanged() {
      if (ShellState.isLoaded) {
        loadState();
      }
    }
  }

  Connections {
    target: ImageCacheService
    function onAdmissionReadyChanged() {
      updateNotificationServer();
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      updateNotificationServer();
    }
    function onEffectiveSettingsChanged(section) {
      if (section === "notifications")
        updateNotificationServer();
    }
  }

  // Helper function to generate content-based ID for deduplication
  function getContentId(summary, body, appName) {
    return Checksum.sha256(JSON.stringify({
                                            "summary": summary || "",
                                            "body": body || "",
                                            "app": appName || ""
                                          }));
  }

  // Main handler
  function handleNotification(notification) {
    const quickshellId = notification.id;
    const data = createData(notification);
    const ruleAction = NotificationRulesService.evaluate(data.appName, data.summary, data.body);
    if (ruleAction === "block")
      return;
    const history = shouldSaveToHistory(data, notification);
    const popup = ruleAction !== "hide" && !root.doNotDisturb && !PowerProfileService.atmospheraPerformanceMode;
    if (!history && !popup)
      return;
    const existingInternalId = quickshellIdToInternalId[quickshellId];
    if (existingInternalId && popupState[existingInternalId]) {
      updatePopup(existingInternalId, notification, data);
      return;
    }
    const entry = {
      data: data,
      historyData: data,
      notification: notification,
      watcher: null,
      cachedActions: [],
      popupWanted: popup,
      historyWanted: history,
      imageRequests: [],
      imageRevision: 0,
      metadata: {
        originalId: data.originalId,
        timestamp: data.timestamp.getTime(),
        duration: calculateDuration(data),
        urgency: data.urgency,
        paused: false,
        pauseTime: 0
      }
    };
    popupState[data.id] = entry;
    quickshellIdToInternalId[quickshellId] = data.id;
    entry.watcher = notificationWatcherComponent.createObject(root, {
                                                                targetNotification: notification,
                                                                targetDataId: data.id
                                                              });
    cacheActions(entry);
    entry.onClosed = function () {
      // The native object is destroyed after this signal. History and its
      // capture keep their own lifetime, never a dangling native reference.
      entry.notification = null;
      entry.cachedActions = [];
      entry.watcher?.destroy();
      entry.watcher = null;
      delete quickshellIdToInternalId[quickshellId];
      dismissPopup(data.id);
    };
    notification.closed.connect(entry.onClosed);
    notification.tracked = true;
    queueImage(entry);
    if (history)
      addToHistory(entry);
    if (popup) {
      const duplicateId = findDuplicateNotification(data);
      if (duplicateId)
        removePopup(duplicateId);
      addPopup(entry);
    }
    if (popup && ruleAction !== "mute")
      playNotificationSound(data.urgency, data.appName);
  }

  function playNotificationSound(urgency, appName) {
    if (!SoundService.multimediaAvailable) {
      return;
    }
    if (!Settings.data.notifications?.sounds?.enabled) {
      return;
    }
    if (AudioService.muted) {
      return;
    }
    if (appName) {
      const excludedApps = Settings.data.notifications.sounds.excludedApps || "";
      if (excludedApps.trim() !== "") {
        const excludedList = excludedApps.toLowerCase().split(',').map(app => app.trim());
        const normalizedName = appName.toLowerCase();

        if (excludedList.includes(normalizedName)) {
          Logger.i("NotificationService", `Skipping sound for excluded app: ${appName}`);
          return;
        }
      }
    }

    // Get the sound file for this urgency level
    const soundFile = getNotificationSoundFile(urgency);
    if (!soundFile || soundFile.trim() === "") {
      // No sound file configured for this urgency level
      Logger.i("NotificationService", `No sound file configured for urgency ${urgency}`);
      return;
    }

    // Rate limiting - prevent sound spam
    const now = Date.now();
    if (now - lastSoundTime < minSoundInterval) {
      return;
    }
    lastSoundTime = now;

    // Play sound using existing SoundService
    const volume = Settings.data.notifications?.sounds?.volume ?? 0.5;
    SoundService.playSound(soundFile, {
                             volume: volume,
                             fallback: false,
                             repeat: false
                           });
  }

  // Get the appropriate sound file path for a given urgency level
  function getNotificationSoundFile(urgency) {
    const settings = Settings.data.notifications?.sounds;
    if (!settings) {
      return "";
    }

    // Default sound file path
    const defaultSoundFile = Quickshell.shellDir + "/Assets/Sounds/notification-generic.wav";

    // If separate sounds is disabled, always use normal sound for all urgencies
    if (!settings.separateSounds) {
      const soundFile = settings.normalSoundFile;
      if (soundFile && soundFile.trim() !== "") {
        return soundFile;
      }
      // Return default if no sound file configured
      return defaultSoundFile;
    }

    // Map urgency levels to sound file keys (when separate sounds is enabled)
    let soundKey;
    switch (urgency) {
    case 0:
      soundKey = "lowSoundFile";
      break;
    case 1:
      soundKey = "normalSoundFile";
      break;
    case 2:
      soundKey = "criticalSoundFile";
      break;
    default:
      // Default to normal urgency for invalid values
      soundKey = "normalSoundFile";
      break;
    }

    const soundFile = settings[soundKey];
    if (soundFile && soundFile.trim() !== "") {
      return soundFile;
    }

    // Return default sound file if none configured for this urgency level
    return defaultSoundFile;
  }

  function updatePopup(internalId, notification, data) {
    const entry = popupState[internalId];
    if (!entry)
      return;
    const rule = NotificationRulesService.evaluate(data.appName, data.summary, data.body);
    if (rule === "block") {
      dismissPopup(internalId);
      return;
    }
    const retained = entry.data;
    data.id = internalId;
    data.timestamp = retained.timestamp;
    const index = findPopupIndex(internalId);
    data.progress = index >= 0 ? popupModel.get(index).progress : retained.progress;
    entry.data = data;
    // Persistence policy applies to the new revision, not permission to erase
    // a previously admitted record (or cancel its still-pending capture).
    const updateHistory = entry.historyWanted && shouldSaveToHistory(data, notification);
    if (updateHistory) {
      const previousHistory = entry.historyData;
      entry.historyData = Object.assign({}, data);
      keepSnapshot(entry.historyData, previousHistory);
    }
    keepSnapshot(data, retained);
    entry.metadata.urgency = data.urgency;
    entry.metadata.duration = calculateDuration(data);
    cacheActions(entry);
    if (rule === "hide" || root.doNotDisturb || PowerProfileService.atmospheraPerformanceMode)
      dismissPopup(internalId);
    if (popupState[internalId] !== entry)
      return;
    const targets = [];
    if (entry.popupWanted)
      targets.push(data);
    if (updateHistory)
      targets.push(entry.historyData);
    if (targets.length)
      queueImage(entry, targets);
    // Subscribe before releasing obsolete targets. The image owner can then
    // share an in-flight acquisition of identical inputs, including a remote
    // URL, without restarting the transfer or keeping the obsolete targets.
    releaseUnusedImages(entry);
    publishEntry(entry);
  }

  function keepSnapshot(data, previous) {
    if (data.originalImage === previous.originalImage)
      data.imageRevision = previous.imageRevision;
    if (!data.originalImage || previous.imageState !== "ready")
      return;
    for (const key of ["cachedImage", "imageState", "imageRevision", "imageFormat", "imageRepresentation", "imageContentSha256"])
      data[key] = previous[key];
  }

  function cacheActions(entry) {
    entry.cachedActions = (entry.notification?.actions || []).map(action => ({
      identifier: action.identifier,
      actionObject: action
    }));
  }

  function publishEntry(entry) {
    for (const target of [
           {
             model: popupModel,
             data: entry.data
           },
           {
             model: historyModel,
             data: entry.historyData
           }
         ]) {
      const model = target.model;
      for (var i = 0; i < model.count; ++i) {
        if (model.get(i).id === entry.data.id) {
          model.set(i, target.data);
          break;
        }
      }
    }
    if (entry.historyWanted)
      saveHistory();
  }

  function addPopup(entry) {
    // Defer list insertion to prevent re-entrant QML incubation crash.
    // Direct insert triggers Repeater.modelUpdated synchronously, which
    // incubates delegates whose signal handlers can re-enter the V4 engine
    // and crash in QV4::Object::insertMember.
    Qt.callLater(() => {
      if (popupState[entry.data.id] !== entry || !entry.popupWanted)
        return;
      popupModel.insert(0, entry.data);

      // Remove overflow
      while (popupModel.count > maxPopups) {
        const last = popupModel.get(popupModel.count - 1);
        // Overflow only removes from ACTIVE view, but keeps it for history
        dismissPopup(last.id);
      }
    });
  }

  function findDuplicateNotification(data) {
    const contentId = getContentId(data.summary, data.body, data.appName);

    for (var i = 0; i < popupModel.count; i++) {
      const existing = popupModel.get(i);
      const existingContentId = getContentId(existing.summary, existing.body, existing.appName);
      if (existingContentId === contentId) {
        return existing.id;
      }
    }
    return null;
  }

  function calculateDuration(data) {
    const durations = [Settings.data.notifications?.lowUrgencyDuration * 1000 || 3000, Settings.data.notifications?.normalUrgencyDuration * 1000 || 8000, Settings.data.notifications?.criticalUrgencyDuration * 1000 || 15000];

    if (Settings.data.notifications?.respectExpireTimeout) {
      if (data.expireTimeout === 0)
        return -1; // Never expire
      if (data.expireTimeout > 0)
        return data.expireTimeout;
    }

    return durations[data.urgency];
  }

  function createData(n) {
    const time = new Date();
    const id = Checksum.sha256(JSON.stringify({
                                                "summary": n.summary,
                                                "body": n.body,
                                                "app": n.appName,
                                                "time": time.getTime(),
                                                "serial": ++root.admissionSerial
                                              }));

    const appIcon = String(n.appIcon || "");
    const arbitraryIcon = appIcon.startsWith("/") || /^(file:|https?:|data:|image:\/\/)/.test(appIcon);
    const image = String(n.image || (arbitraryIcon ? appIcon : ""));

    return {
      "id": id,
      "summary": processNotificationText(n.summary || ""),
      "summaryMarkdown": processNotificationMarkdown(n.summary || ""),
      "body": processNotificationText(n.body || ""),
      "bodyMarkdown": processNotificationMarkdown(n.body || ""),
      "appName": getAppName(n.appName || n.desktopEntry || ""),
      "urgency": n.urgency < 0 || n.urgency > 2 ? 1 : n.urgency,
      "expireTimeout": n.expireTimeout,
      "timestamp": time,
      "progress": 1.0,
      "originalImage": image,
      "cachedImage": "",
      "iconName": arbitraryIcon ? "" : appIcon,
      "imageState": image ? "loading" : "idle",
      "imageRevision": "",
      "imageFormat": "",
      "imageRepresentation": "",
      "imageContentSha256": "",
      "imageErrorCode": "",
      "imageErrorReason": "",
      "originalId": n.originalId || n.id || 0 // Ensure originalId is passed through
                    ,
      "actionsJson": JSON.stringify((n.actions || []).map(a => ({
        "text": (a.text || "").trim() || "Action",
        "identifier": a.identifier || ""
      })))
  };
  }

    function findPopupIndex(internalId) {
    for (var i = 0; i < popupModel.count; i++) {
    if (popupModel.get(i).id === internalId) {
    return i;
  }
  }
    return -1;
  }

    function updateNotificationFromObject(internalId) {
    const notifData = popupState[internalId];
    if (!notifData?.watcher || !notifData.notification)
    return;
    const data = createData(notifData.notification);
    updatePopup(internalId, notifData.notification, data);
  }

    function removePopup(id) {
    dismissPopup(id);
  }

    function cleanupNotification(id) {
    const notifData = popupState[id];
    if (notifData) {
    if (notifData.popupWanted || notifData.historyWanted)
    return;
    for (const request of notifData.imageRequests)
    request.interest?.cancel();
    notifData.imageRequests = [];
    if (notifData.notification && notifData.onClosed) {
    try {
    notifData.notification.closed.disconnect(notifData.onClosed);
  } catch (e) {}
  }
    notifData.watcher?.destroy();
    delete popupState[id];
    notifData.notification?.dismiss();
  }

    // Clean up quickshell ID mapping
    for (const qsId in quickshellIdToInternalId) {
    if (quickshellIdToInternalId[qsId] === id) {
    delete quickshellIdToInternalId[qsId];
    break;
  }
  }
  }

    // Progress updates
    Timer {
    interval: 50
    repeat: true
    running: popupModel.count > 0
    onTriggered: updateAllProgress()
  }

    function updateAllProgress() {
    const now = Date.now();
    const toRemove = [];

    for (var i = 0; i < popupModel.count; i++) {
    const notif = popupModel.get(i);
    const notifData = popupState[notif.id];
    if (!notifData)
    continue;
    const meta = notifData.metadata;
    if (meta.duration === -1 || meta.paused)
    continue;
    const elapsed = now - meta.timestamp;
    const progress = Math.max(1.0 - (elapsed / meta.duration), 0.0);

    if (progress <= 0) {
    toRemove.push(notif.id);
  } else if (Math.abs(notif.progress - progress) > 0.005) {
    popupModel.setProperty(i, "progress", progress);
  }
  }

    if (toRemove.length > 0) {
    animateAndRemove(toRemove[0]);
  }
  }

    // Capture runs in the producer's signal stack. Only decoding and retained
    // publication are asynchronous. Own the attempt by its target records, not
    // their displayed revision, which may still refer to a previous snapshot.
    function queueImage(entry, targets = [entry.data]) {
    let revision = "";
    function newRevision() {
    if (!revision)
    revision = entry.data.id + ":" + ++entry.imageRevision;
    return revision;
  }
    for (const data of targets) {
    if (!data.imageRevision)
    data.imageRevision = newRevision();
  }
    if (!entry.data.originalImage)
    return;
    const request = {
    targets: targets,
    interest: null,
    pending: true
  };
    entry.imageRequests.push(request);
    const interest = ImageCacheService.getNotificationIcon(entry.data.originalImage, "", "", function (path, success, detail) {
    request.interest = null;
    request.pending = false;
    if (popupState[entry.data.id] !== entry)
    return;
    for (const data of request.targets) {
    if (!ownsImage(entry, data))
    continue;
    if (data.imageState === "ready") {
    // A capture attempt is not a new snapshot. The retention owner
    // hashes the captured content independently of source and cache URLs.
    if (!success || detail.contentSha256 === data.imageContentSha256)
    continue;
    data.imageRevision = newRevision();
  }
    data.cachedImage = success ? PortalPaths.pathToUri(path).uri : "";
    data.imageState = success ? "ready" : "unavailable";
    data.imageContentSha256 = success ? detail.contentSha256 : "";
    data.imageFormat = success ? String(detail.originalFormat || "") : "";
    data.imageRepresentation = success ? String(detail.url || "") : "";
    data.imageErrorCode = success ? "" : String(detail.code || "image-unavailable");
    data.imageErrorReason = success ? "" : String(detail.reason || "The notification image is unavailable");
  }
    releaseUnusedImages(entry);
    publishEntry(entry);
  });
    if (request.pending)
    request.interest = interest;
  }

    function ownsImage(entry, data) {
    return (entry.popupWanted && entry.data === data) || (entry.historyWanted && entry.historyData === data);
  }

    function releaseUnusedImages(entry) {
    entry.imageRequests = entry.imageRequests.filter(request => {
    if (request.pending && request.targets.some(data => ownsImage(entry, data)))
    return true;
    request.interest?.cancel();
    return false;
  });
  }

    function updateModel(model, notificationId, prop, value) {
    for (var i = 0; i < model.count; i++) {
    if (model.get(i).id === notificationId) {
    model.setProperty(i, prop, value);
    break;
  }
  }
  }

    // History management
    function shouldSaveToHistory(data, notification) {
    if (notification.transient)
    return false;
    const s = Settings.data.notifications?.saveToHistory;
    if (s) {
    let ok = true;
    if (data.urgency === 0)
    ok = s.low !== false;
    else if (data.urgency === 1)
    ok = s.normal !== false;
    else if (data.urgency === 2)
    ok = s.critical !== false;
    return ok;
  } else {
    return true;
  }
  }

    function addToHistory(entry) {
    // Defer list insertion to prevent re-entrant QML incubation crash.
    // See addPopup for full explanation.
    Qt.callLater(() => {
    if (popupState[entry.data.id] !== entry || !entry.historyWanted)
    return;
    historyModel.insert(0, entry.historyData);

    while (historyModel.count > maxHistory) {
    const old = historyModel.get(historyModel.count - 1);
    removeFromHistory(old.id);
  }
    saveHistory();
  });
  }

    // Persistence - History
    FileView {
    id: historyFileView
    path: historyFile
    printErrors: false
    onLoaded: loadHistory()
    onLoadFailed: error => {
    if (error === 2)
    writeAdapter();
  }

    JsonAdapter {
    id: adapter
    property var notifications: []
  }
  }

    Timer {
    id: saveTimer
    interval: 200
    onTriggered: performSaveHistory()
  }

    function saveHistory() {
    saveTimer.restart();
  }

    function performSaveHistory() {
    try {
    const items = [];
    for (var i = 0; i < historyModel.count; i++) {
    const n = historyModel.get(i);
    const copy = Object.assign({}, n);
    copy.timestamp = n.timestamp.getTime();
    items.push(copy);
  }
    adapter.notifications = items;
    historyFileView.writeAdapter();
  } catch (e) {
    Logger.e("Notifications", "Save history failed:", e);
  }
  }

    function loadHistory() {
    try {
    historyModel.clear();
    for (const item of adapter.notifications || []) {
    const time = new Date(item.timestamp);

    // A cold reader never reacquires a producer-owned original. Legacy records
    // without retained bytes are explicit unavailable images, not false success.
    const cachedImage = String(item.cachedImage || "");
    const retained = cachedImage && (cachedImage.startsWith("file://") || cachedImage.startsWith("/")) && (item.imageState === "ready" || cachedImage !== item.originalImage);
    const requested = !!item.originalImage && (item.imageState !== undefined || /^(\/|file:|https?:|data:|image:\/\/)/.test(item.originalImage));

    historyModel.append({
    "id": item.id || "",
    "summary": item.summary || "",
    "summaryMarkdown": processNotificationMarkdown(item.summary || ""),
    "body": item.body || "",
    "bodyMarkdown": processNotificationMarkdown(item.body || ""),
    "appName": item.appName || "",
    "urgency": item.urgency < 0 || item.urgency > 2 ? 1 : item.urgency,
    "timestamp": time,
    "originalImage": item.originalImage || "",
    "cachedImage": retained ? cachedImage : "",
    "iconName": item.iconName || (!requested ? "" : (!/^(\/|file:|https?:|data:|image:\/\/)/.test(item.originalImage) ? item.originalImage : "")),
    "imageState": retained ? "ready" : requested ? "unavailable" : "idle",
    "imageRevision": item.imageRevision || "",
    "imageFormat": item.imageFormat || "",
    "imageRepresentation": item.imageRepresentation || "",
    "imageErrorCode": retained || !requested ? "" : item.imageErrorCode || "retained-image-missing",
    "imageErrorReason": retained || !requested ? "" : item.imageErrorReason || "The notification image was not retained",
    "actionsJson": item.actionsJson || "[]",
    "originalId": item.originalId || 0
  });
  }
  } catch (e) {
    Logger.e("Notifications", "Load failed:", e);
  }
  }

    function loadState() {
    try {
    const notifState = ShellState.getNotificationsState();
    root.lastSeenTs = notifState.lastSeenTs || 0;

    // Migration is now handled in Settings.qml
    Logger.d("Notifications", "Loaded state from ShellState");
  } catch (e) {
    Logger.e("Notifications", "Load state failed:", e);
  }
  }

    function saveState() {
    try {
    ShellState.setNotificationsState({
    lastSeenTs: root.lastSeenTs
  });
    Logger.d("Notifications", "Saved state to ShellState");
  } catch (e) {
    Logger.e("Notifications", "Save state failed:", e);
  }
  }

    function updateLastSeenTs() {
    root.lastSeenTs = Time.timestamp * 1000;
    saveState();
  }

    // Utility functions
    function getAppName(name) {
    if (!name || name.trim() === "")
    return "Unknown";
    name = name.trim();

    if (name.includes(".") && (name.startsWith("com.") || name.startsWith("org.") || name.startsWith("io.") || name.startsWith("net."))) {
    const parts = name.split(".");
    let appPart = parts[parts.length - 1];

    if (!appPart || appPart === "app" || appPart === "desktop") {
    appPart = parts[parts.length - 2] || parts[0];
  }

    if (appPart)
    name = appPart;
  }

    if (name.includes(".")) {
    const parts = name.split(".");
    let displayName = parts[parts.length - 1];

    if (!displayName || /^\d+$/.test(displayName)) {
    displayName = parts[parts.length - 2] || parts[0];
  }

    if (displayName) {
    displayName = displayName.charAt(0).toUpperCase() + displayName.slice(1);
    displayName = displayName.replace(/([a-z])([A-Z])/g, '$1 $2');
    displayName = displayName.replace(/app$/i, '').trim();
    displayName = displayName.replace(/desktop$/i, '').trim();
    displayName = displayName.replace(/flatpak$/i, '').trim();

    if (!displayName) {
    displayName = parts[parts.length - 1].charAt(0).toUpperCase() + parts[parts.length - 1].slice(1);
  }
  }

    return displayName || name;
  }

    let displayName = name.charAt(0).toUpperCase() + name.slice(1);
    displayName = displayName.replace(/([a-z])([A-Z])/g, '$1 $2');
    displayName = displayName.replace(/app$/i, '').trim();
    displayName = displayName.replace(/desktop$/i, '').trim();

    return displayName || name;
  }

    function getIcon(icon) {
    if (!icon)
    return "";
    if (icon.startsWith("/") || icon.startsWith("file://"))
    return icon;
    return icon;
  }

    function escapeHtml(text) {
    if (!text)
    return "";
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

    function sanitizeMarkdownUrl(url) {
    if (!url)
    return "";
    const trimmed = url.trim();
    if (trimmed === "")
    return "";
    const lower = trimmed.toLowerCase();
    if (lower.startsWith("http://") || lower.startsWith("https://") || lower.startsWith("mailto:")) {
    return encodeURI(trimmed);
  }
    return "";
  }

    function sanitizeMarkdown(text) {
    if (!text)
    return "";

    let input = String(text);

    // Strip images entirely
    input = input.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, function (match, alt) {
    return alt ? alt : "";
  });

    // Extract links into placeholders
    const links = [];
    input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function (match, label, urlAndTitle) {
    const urlPart = (urlAndTitle || "").trim().split(/\s+/)[0] || "";
    const safeUrl = sanitizeMarkdownUrl(urlPart);
    const safeLabel = escapeHtml(label);
    if (!safeUrl)
    return safeLabel;
    const token = "__MDLINK_" + links.length + "__";
    links.push({
    "label": safeLabel,
    "url": safeUrl
  });
    return token;
  });

    // Escape any remaining HTML
    input = escapeHtml(input);

    // Restore sanitized links
    for (let i = 0; i < links.length; i++) {
    const token = "__MDLINK_" + i + "__";
    const link = links[i];
    input = input.split(token).join("[" + link.label + "](" + link.url + ")");
  }

    return input;
  }

    function processNotificationText(text) {
    if (!text)
    return "";

    // Split by tags to process segments separately
    const parts = text.split(/(<[^>]+>)/);
    let result = "";
    const allowedTags = ["b", "i", "u", "a", "br"];

    for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (part.startsWith("<") && part.endsWith(">")) {
    const content = part.substring(1, part.length - 1);
    const firstWord = content.split(/[\s/]/).filter(s => s.length > 0)[0]?.toLowerCase();

    if (allowedTags.includes(firstWord)) {
    // Preserve valid HTML tag
    result += part;
  } else {
    // Unknown tag: drop tag without leaking attributes
    result += "";
  }
  } else {
    // Normal text: escape everything
    result += escapeHtml(part);
  }
  }
    return result;
  }

    function processNotificationMarkdown(text) {
    return sanitizeMarkdown(text);
  }

    function pauseTimeout(id) {
    const notifData = popupState[id];
    if (notifData && !notifData.metadata.paused) {
    notifData.metadata.paused = true;
    notifData.metadata.pauseTime = Date.now();
  }
  }

    function resumeTimeout(id) {
    const notifData = popupState[id];
    if (notifData && notifData.metadata.paused) {
    notifData.metadata.timestamp += Date.now() - notifData.metadata.pauseTime;
    notifData.metadata.paused = false;
  }
  }

    // Dismiss a popup notification (e.g. clicked close, swipe, or overflow).
    // Removes from popup list but KEEPS data for history.
    function dismissPopup(id) {
    const entry = popupState[id];
    if (entry)
    entry.popupWanted = false;
    if (entry)
    releaseUnusedImages(entry);
    const index = findPopupIndex(id);
    if (index >= 0) {
    popupModel.remove(index);
  }
    cleanupNotification(id);
  }

    function dismissOldestPopup() {
    if (popupModel.count > 0) {
    const lastNotif = popupModel.get(popupModel.count - 1);
    dismissPopup(lastNotif.id);
  }
  }

    function dismissAllPopups() {
    for (const id in popupState) {
    dismissPopup(id);
  }
    popupModel.clear();
  }

    function invokeActionAndSuppressClose(id, actionId) {
    const notifData = popupState[id];
    const notification = notifData?.notification;
    const onClosed = notifData?.onClosed;
    let restoreClosedHandler = false;

    if (notification && onClosed) {
    try {
    // A successful action may synchronously close the notification. Disconnect
    // our close handler first so the popup is only dismissed by the action path.
    notification.closed.disconnect(onClosed);
    restoreClosedHandler = true;
  } catch (e) {}
  }

    const invoked = invokeAction(id, actionId);

    if (!invoked && restoreClosedHandler && notification && onClosed) {
    try {
    // If invoking the action failed, restore normal close handling for this popup.
    notification.closed.connect(onClosed);
  } catch (e) {}
  }

    return invoked;
  }

    function invokeAction(id, actionId) {
    let invoked = false;
    const notifData = popupState[id];

    if (notifData && notifData.notification) {
    const actionsToUse = (notifData.notification.actions && notifData.notification.actions.length > 0) ? notifData.notification.actions : (notifData.cachedActions || []);

    if (actionsToUse && actionsToUse.length > 0) {
    for (const item of actionsToUse) {
    const itemId = item.identifier;
    const actionObj = item.actionObject ? item.actionObject : item;

    if (itemId === actionId) {
    if (actionObj.invoke) {
    try {
    actionObj.invoke();
    invoked = true;
  } catch (e) {
    Logger.w("NotificationService", "invoke() failed, trying manual fallback: " + e);
    if (manualInvoke(notifData.metadata.originalId, itemId)) {
    invoked = true;
  }
  }
  } else {
    if (manualInvoke(notifData.metadata.originalId, itemId)) {
    invoked = true;
  }
  }
    break;
  }
  }
  }

    if (!invoked && notifData.metadata.originalId) {
    Logger.w("NotificationService", "Action objects exhausted, trying manual invoke for id=" + id + " action=" + actionId);
    invoked = manualInvoke(notifData.metadata.originalId, actionId);
  }
  } else if (!notifData) {
    Logger.w("NotificationService", "No active notification data for id=" + id + ", searching history for manual invoke");
    for (var i = 0; i < historyModel.count; i++) {
    if (historyModel.get(i).id === id) {
    const histEntry = historyModel.get(i);
    if (histEntry.originalId) {
    invoked = manualInvoke(histEntry.originalId, actionId);
  }
    break;
  }
  }
  }

    if (!invoked) {
    Logger.w("NotificationService", "Failed to invoke action '" + actionId + "' for notification " + id);
    return false;
  }

    // Clear actions after use
    updateModel(popupModel, id, "actionsJson", "[]");
    updateModel(historyModel, id, "actionsJson", "[]");
    saveHistory();

    return true;
  }

    function manualInvoke(originalId, actionId) {
    if (!originalId) {
    return false;
  }

    try {
    // Construct the signal emission using dbus-send
    // dbus-send --session --type=signal /org/freedesktop/Notifications org.freedesktop.Notifications.ActionInvoked uint32:ID string:"KEY"
    const args = ["dbus-send", "--session", "--type=signal", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.ActionInvoked", "uint32:" + originalId, "string:" + actionId];

    Quickshell.execDetached(args);
    return true;
  } catch (e) {
    Logger.e("NotificationService", "Manual invoke failed: " + e);
    return false;
  }
  }

    function focusSenderWindow(appName) {
    if (!appName || appName === "" || appName === "Unknown")
    return false;

    const normalizedName = appName.toLowerCase().replace(/\s+/g, "");

    for (var i = 0; i < CompositorService.windows.count; i++) {
    const win = CompositorService.windows.get(i);
    const winAppId = (win.appId || "").toLowerCase();

    const segments = winAppId.split(".");
    const lastSegment = segments[segments.length - 1] || "";

    if (winAppId === normalizedName || lastSegment === normalizedName || winAppId.includes(normalizedName) || normalizedName.includes(lastSegment)) {
    CompositorService.focusWindow(win);
    return true;
  }
  }

    Logger.d("NotificationService", "No window found for app: " + appName);
    return false;
  }

    function removeFromHistory(notificationId) {
    const entry = popupState[notificationId];
    const pending = !!entry?.historyWanted;
    if (entry)
    entry.historyWanted = false;
    if (entry)
    releaseUnusedImages(entry);
    for (var i = 0; i < historyModel.count; i++) {
    const notif = historyModel.get(i);
    if (notif.id === notificationId) {
    historyModel.remove(i);
    saveHistory();
    cleanupNotification(notificationId);
    return true;
  }
  }
    cleanupNotification(notificationId);
    if (pending)
    saveHistory();
    return pending;
  }

    function removeOldestHistory() {
    if (historyModel.count > 0) {
    const oldest = historyModel.get(historyModel.count - 1);
    return removeFromHistory(oldest.id);
  }
    return false;
  }

    function clearHistory() {
    // Retained bytes are immutable and may be shared with another entry or
    // process. Membership owns interests, never permission to unlink sources.
    for (const id in popupState) {
    popupState[id].historyWanted = false;
    releaseUnusedImages(popupState[id]);
    cleanupNotification(id);
  }

    historyModel.clear();
    saveHistory();
  }

    function getHistorySnapshot() {
    const items = [];
    for (var i = 0; i < historyModel.count; i++) {
    const entry = historyModel.get(i);
    items.push({
    "id": entry.id,
    "summary": entry.summary,
    "body": entry.body,
    "appName": entry.appName,
    "urgency": entry.urgency,
    "timestamp": entry.timestamp instanceof Date ? entry.timestamp.getTime() : entry.timestamp,
    "originalImage": entry.originalImage,
    "cachedImage": entry.cachedImage
  });
  }
    return items;
  }

    // Signals
    signal animateAndRemove(string notificationId)

    onDoNotDisturbChanged: {
    ToastService.showNotice(doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled") : I18n.tr("toast.do-not-disturb.disabled"), doNotDisturb ? I18n.tr("toast.do-not-disturb.enabled-desc") : I18n.tr("toast.do-not-disturb.disabled-desc"), doNotDisturb ? "bell-off" : "bell");
  }

    // Media toast functionality
    property string previousMediaTitle: ""
    property string previousMediaArtist: ""
    property bool previousMediaIsPlaying: false
    property bool mediaToastInitialized: false

    Timer {
    id: mediaToastInitTimer
    interval: 3000 // Wait 3 seconds after startup to avoid initial toast
    running: true
    onTriggered: {
    root.mediaToastInitialized = true;
    root.previousMediaTitle = MediaService.trackTitle;
    root.previousMediaArtist = MediaService.trackArtist;
    root.previousMediaIsPlaying = MediaService.isPlaying;
  }
  }

    Timer {
    id: mediaToastDebounce
    interval: 250 // Dynamic interval based on player
    onTriggered: {
    checkMediaToast();
  }
  }

    function checkMediaToast() {
    if (!Settings.data.notifications.enableMediaToast || !mediaToastInitialized)
    return;

    if (doNotDisturb || PowerProfileService.atmospheraPerformanceMode)
    return;

    // Re-evaluate player identity here to handle race conditions where
    // the identity wasn't updated yet when the timer started.
    const player = (MediaService.playerIdentity || "").toLowerCase();
    const browsers = ["firefox", "chromium", "chrome", "brave", "edge", "opera", "vivaldi", "zen"];
    const isBrowser = browsers.some(b => player.includes(b));

    // Safety check: If it's a browser, ensure we waited long enough.
    // If we started with a short interval (e.g. 250ms because we thought it was Spotify),
    // correct it now and wait the full duration.
    if (isBrowser && mediaToastDebounce.interval < 1500) {
    mediaToastDebounce.interval = 1500;
    mediaToastDebounce.restart();
    return;
  }

    const title = MediaService.trackTitle || "";
    const artist = MediaService.trackArtist || "";
    const isPlaying = MediaService.isPlaying;

    // Only show toast if something meaningful changed
    const titleChanged = title !== previousMediaTitle && title !== "";
    const playStateChanged = isPlaying !== previousMediaIsPlaying;
    const hasMedia = title !== "" || artist !== "";

    // Browser Specific Logic:
    // If a browser reports a new title but is PAUSED, ignore it.
    if (isBrowser && !isPlaying && titleChanged) {
    previousMediaTitle = title;
    previousMediaArtist = artist;
    previousMediaIsPlaying = isPlaying;
    return;
  }

    if (hasMedia && (titleChanged || playStateChanged)) {
    const icon = isPlaying ? "media-play" : "media-pause";
    let message = "";

    if (artist && title) {
    message = artist + " — " + title;
  } else if (title) {
    message = title;
  } else if (artist) {
    message = artist;
  }

    if (message !== "") {
    const toastTitle = isPlaying ? I18n.tr("common.play") : I18n.tr("common.pause");
    ToastService.showNotice(toastTitle, message, icon, 3000);
  }
  }

    previousMediaTitle = title;
    previousMediaArtist = artist;
    previousMediaIsPlaying = isPlaying;
  }

    Connections {
    target: MediaService

    function onTrackTitleChanged() {
    restartDebounce();
  }

    function onTrackArtistChanged() {
    restartDebounce();
  }

    function onIsPlayingChanged() {
    restartDebounce();
  }

    function onPlayerIdentityChanged() {
    restartDebounce();
  }
  }

    function restartDebounce() {
    const player = (MediaService.playerIdentity || "").toLowerCase();
    const browsers = ["firefox", "chromium", "chrome", "brave", "edge", "opera", "vivaldi"];
    const isBrowser = browsers.some(b => player.includes(b));

    // Use long delay for browsers to filter hover previews, short for music apps
    mediaToastDebounce.interval = isBrowser ? 1500 : 250;
    mediaToastDebounce.restart();
  }
  }
