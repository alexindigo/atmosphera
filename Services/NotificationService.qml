pragma Singleton

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import "../Helpers/sha256.js" as Checksum

Singleton {
  id: root

  // ===== Configuration =====
  property int maxVisible: 5
  property int maxHistory: 100
  property string historyFile: Quickshell.env("NOCTALIA_NOTIF_HISTORY_FILE") || (Settings.cacheDir + "notifications.json")

  // ===== Models =====
  property ListModel activeNotifications: ListModel {}
  property ListModel notificationHistory: ListModel {}

  // ===== Internal tracking =====
  property var activeNotificationMap: ({}) // Maps notification ID to raw notification object
  property var cachingQueue: ({}) // Maps notification ID to caching status

  // ===== Image caching window =====
  property PanelWindow imageCachingWindow: PanelWindow {
    id: imageCachingWindow

    width: 1
    height: 1
    color: "transparent"
    mask: Region {}

    Item {
      id: cachingContainer
      width: 256
      height: 256

      Image {
        id: imageCacher
        anchors.fill: parent
        visible: true // Must be visible for grabToImage to work
        cache: false // Disable QML cache since we're doing disk cache
        mipmap: true
        smooth: true
        asynchronous: true
        antialiasing: true

        property string currentNotificationId: ""
        property string targetCachePath: ""

        onStatusChanged: {
          if (status === Image.Ready && currentNotificationId && targetCachePath) {
            // Logger.log("Notification", "Image loaded successfully, attempting to cache to:", targetCachePath)

            // Create cache directory if it doesn't exist using mkdir
            try {
              Quickshell.execDetached(["mkdir", "-p", Settings.cacheDirImagesNotifications])
            } catch (e) {
              Logger.error("Notification", "Failed to create cache directory:", e)
            }

            // Cache the image to disk
            grabToImage(function (result) {
              if (result.saveToFile(targetCachePath)) {
                //Logger.log("Notification", "Successfully cached image to:", targetCachePath)
                // Update the notification data with cached path
                updateNotificationCachedImage(currentNotificationId, targetCachePath)
              } else {
                Logger.error("Notification", "Failed to save cached image:", targetCachePath)
              }

              // Clear current caching operation
              currentNotificationId = ""
              targetCachePath = ""
              source = ""

              // Process next item in queue if any
              processNextCacheRequest()
            })
          } else if (status === Image.Error) {
            Logger.error("Notification", "Failed to load image for caching:", source, "error for:", currentNotificationId)

            // Clear current caching operation and process next
            currentNotificationId = ""
            targetCachePath = ""
            source = ""
            processNextCacheRequest()
          }
        }
      }
    }
  }

  // ===== Convenience property to access the image cacher =====
  property alias imageCacher: imageCacher

  // ===== Notification Server =====
  property NotificationServer server: NotificationServer {
    id: notificationServer

    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    actionIconsSupported: true
    bodyMarkupSupported: true
    bodySupported: true
    persistenceSupported: true
    inlineReplySupported: true
    bodyHyperlinksSupported: true
    bodyImagesSupported: true

    onNotification: function (notification) {
      root.handleIncomingNotification(notification)
    }
  }

  // ===== Main notification handler =====
  function handleIncomingNotification(notification) {
    // Create standardized notification data
    const notifData = createNotificationData(notification)

    // Always add to history
    addToHistory(notifData)

    // Check do-not-disturb
    if (Settings.data.notifications?.doNotDisturb) {
      return
    }

    // Track the raw notification for dismissal
    notification.tracked = true
    activeNotificationMap[notifData.id] = notification

    // Handle notification closure
    notification.closed.connect(function () {
      removeActiveNotification(notifData.id)
    })

    // Add to active notifications
    addActiveNotification(notifData)
  }

  // ===== Data creation =====
  function createNotificationData(notification) {

    //console.log(JSON.stringify(notification))
    const timestamp = new Date()
    const id = generateNotificationId(notification, timestamp)

    // Resolve display values
    const appName = resolveAppName(notification)
    const imagePath = resolveNotificationImage(notification)
    const cachedImagePath = cacheImageIfNeeded(imagePath, id)

    // Process actions to store them in a serializable format
    const actions = []
    if (notification.actions && notification.actions.length > 0) {
      for (let action of notification.actions) {
        actions.push({
                       "text": action.text || "Action",
                       "identifier": action.identifier || ""
                     })
      }
    }

    return {
      "id": id,
      "summary": notification.summary.substring(0, 100) || "",
      "body": strip_tags_regex(notification.body).substring(0, 100) || "",
      "appName": appName,
      "desktopEntry": notification.desktopEntry || "",
      "urgency": notification.urgency || 1,
      "timestamp": timestamp,
      "originalImage": imagePath,
      "cachedImage": cachedImagePath,
      "actionsJson": JSON.stringify(actions)
    }
  }

  function generateNotificationId(notification, timestamp) {
    // Create a unique ID based on notification content and timestamp
    const data = {
      "summary": notification.summary,
      "body": notification.body,
      "appName": notification.appName,
      "timestamp": timestamp.getTime()
    }
    return Checksum.sha256(JSON.stringify(data))
  }

  function cacheImageIfNeeded(imagePath, notificationId) {
    if (!imagePath) {
      return ""
    }

    const destination = Settings.cacheDirImagesNotifications + notificationId + ".png"

    // Handle different image types differently
    if (imagePath.startsWith("image://")) {
      // For image:// URLs, use the Image component to cache
      queueImageForCaching(imagePath, notificationId, destination)
      return imagePath
    } else if (imagePath.startsWith("/") || imagePath.startsWith("file://")) {
      // For local files, use direct copy
      try {
        const sourceFile = imagePath.startsWith("file://") ? imagePath.substring(7) : imagePath

        // Create cache directory and copy file
        Quickshell.execDetached(["sh", "-c", `cp "${sourceFile}" "${destination}"`])
        // Logger.log("Notification", "Initiated direct file copy to:", destination)

        // For direct copies, we assume success and return the destination
        // If the copy failed, the original path will still work
        return destination
      } catch (e) {
        Logger.error("Notification", "File copy failed, using Image fallback:", e)
        queueImageForCaching(imagePath, notificationId, destination)
        return imagePath
      }
    } else {
      // For other URLs or unknown formats, use Image component
      queueImageForCaching(imagePath, notificationId, destination)
      return imagePath
    }
  }

  function queueImageForCaching(imagePath, notificationId, destination) {
    // Add to caching queue
    cachingQueue[notificationId] = {
      "source": imagePath,
      "destination": destination,
      "status": "queued"
    }

    // Start processing if not already busy
    if (!imageCacher.currentNotificationId) {
      processNextCacheRequest()
    }
  }

  function processNextCacheRequest() {
    // Find next queued item
    for (const notifId in cachingQueue) {
      if (cachingQueue[notifId].status === "queued") {
        const request = cachingQueue[notifId]

        // Mark as processing
        cachingQueue[notifId].status = "processing"

        // Set up the image cacher
        imageCacher.currentNotificationId = notifId
        imageCacher.targetCachePath = request.destination
        imageCacher.source = request.source

        //Logger.log("Notification", "Starting image cache for:", notifId, "from:", request.source)
        return
      }
    }
  }

  function updateNotificationCachedImage(notificationId, cachedPath) {
    var updated = false

    // Update active notifications
    for (var i = 0; i < activeNotifications.count; i++) {
      const notif = activeNotifications.get(i)
      if (notif.id === notificationId) {
        activeNotifications.setProperty(i, "cachedImage", cachedPath)
        updated = true
        break
      }
    }

    // Update history
    for (var j = 0; j < notificationHistory.count; j++) {
      const histNotif = notificationHistory.get(j)
      if (histNotif.id === notificationId) {
        notificationHistory.setProperty(j, "cachedImage", cachedPath)
        updated = true
        break
      }
    }

    if (!updated) {
      Logger.warn("Notification", "Could not find notification to update:", notificationId)
    }

    // Remove from caching queue
    delete cachingQueue[notificationId]

    // Save updated history
    if (updated) {
      saveHistory()
      // performHistorySave() // Immediate save for cache updates
    }
  }

  // ===== Active notification management =====
  function addActiveNotification(notifData) {
    activeNotifications.insert(0, notifData)

    // Enforce max visible
    while (activeNotifications.count > maxVisible) {
      const oldest = activeNotifications.get(activeNotifications.count - 1)
      dismissNotification(oldest.id)
      activeNotifications.remove(activeNotifications.count - 1)
    }
  }

  function removeActiveNotification(notificationId) {
    for (var i = 0; i < activeNotifications.count; i++) {
      if (activeNotifications.get(i).id === notificationId) {
        activeNotifications.remove(i)
        delete activeNotificationMap[notificationId]

        // Also clean up any pending cache operations
        if (cachingQueue[notificationId]) {
          delete cachingQueue[notificationId]
        }

        break
      }
    }
  }

  function dismissNotification(notificationId) {
    const rawNotification = activeNotificationMap[notificationId]
    if (rawNotification) {
      rawNotification.dismiss()
    }
    removeActiveNotification(notificationId)
  }

  // ===== Auto-hide timer =====
  property Timer autoHideTimer: Timer {
    interval: 1000
    repeat: true
    running: activeNotifications.count > 0

    onTriggered: {
      const now = new Date().getTime()

      for (var i = activeNotifications.count - 1; i >= 0; i--) {
        const notif = activeNotifications.get(i)
        const elapsed = now - notif.timestamp.getTime()
        const duration = getDurationForUrgency(notif.urgency)

        if (elapsed >= duration) {
          animateAndRemove(notif.id, i)
          break
          // Only remove one per tick for animation
        }
      }
    }
  }

  function getDurationForUrgency(urgency) {
    const durations = Settings.data.notifications || {}
    switch (urgency) {
    case 0:
      return (durations.lowUrgencyDuration || 3) * 1000
    case 1:
      return (durations.normalUrgencyDuration || 8) * 1000
    case 2:
      return (durations.criticalUrgencyDuration || 15) * 1000
    default:
      return 8000
    }
  }

  // ===== Persistence =====
  property FileView historyFileView: FileView {
    id: historyFileView
    path: historyFile
    printErrors: false
    watchChanges: true

    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    Component.onCompleted: reload()
    onLoaded: loadHistoryFromFile()

    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2) {
        writeAdapter() // Create file
      }
    }

    JsonAdapter {
      id: historyAdapter
      property var notifications: []
      property real lastSaved: 0
    }
  }

  property Timer saveHistoryTimer: Timer {
    interval: 200
    repeat: false
    onTriggered: performHistorySave()
  }

  // ===== History management =====H
  function addToHistory(notifData) {
    notificationHistory.insert(0, notifData)

    // Enforce max history - use removeFromHistory to properly clean up cached images
    while (notificationHistory.count > maxHistory) {
      const oldestNotif = notificationHistory.get(notificationHistory.count - 1)
      removeFromHistory(oldestNotif.id)
    }

    saveHistory()
  }

  function removeFromHistory(notificationId) {
    for (var i = 0; i < notificationHistory.count; i++) {
      const notif = notificationHistory.get(i)
      if (notif.id === notificationId) {
        // Delete cached image if it exists
        if (notif.cachedImage && notif.cachedImage.length > 0 && !notif.cachedImage.startsWith("image://")) {
          try {
            // rm -f won't error if file doesn't exist
            Quickshell.execDetached(["rm", "-f", notif.cachedImage])
            //Logger.log("Notifications", "Deleted cached image:", notif.cachedImage)
          } catch (e) {
            Logger.error("Notifications", "Failed to delete cached image:", e)
          }
        }

        notificationHistory.remove(i)
        saveHistory()
        return true
      }
    }
    return false
  }

  function clearHistory() {
    // Remove all images, yay!
    try {
      Quickshell.execDetached(["sh", "-c", `rm -rf "${Settings.cacheDirImagesNotifications}"*`])
    } catch (e) {
      Logger.error("Notifications", "Failed to clear cache directory:", e)
    }

    notificationHistory.clear()
    saveHistory()
  }

  function loadHistoryFromFile() {
    try {
      notificationHistory.clear()
      const items = historyAdapter.notifications || []

      for (const item of items) {
        // Ensure timestamp is properly converted
        let timestamp = item.timestamp
        if (typeof timestamp === "number") {
          if (timestamp < 1e12)
            timestamp *= 1000 // Convert seconds to ms
          timestamp = new Date(timestamp)
        } else if (!(timestamp instanceof Date)) {
          timestamp = new Date()
        }

        notificationHistory.append({
                                     "id": item.id || generateNotificationId(item, timestamp),
                                     "summary": item.summary || "",
                                     "body": item.body || "",
                                     "appName": item.appName || "",
                                     "desktopEntry": item.desktopEntry || "",
                                     "urgency": item.urgency || 1,
                                     "timestamp": timestamp,
                                     "originalImage": item.originalImage || "",
                                     "cachedImage": item.cachedImage || ""
                                   })
      }
    } catch (e) {
      Logger.error("Notifications", "Failed to load history:", e)
    }
  }

  function saveHistory() {
    saveHistoryTimer.restart() // Debounce multiple saves
  }

  function performHistorySave() {
    try {
      const notifications = []

      for (var i = 0; i < notificationHistory.count; i++) {
        const notif = notificationHistory.get(i)

        // Create a shallow copy and fix the timestamp
        const copy = Object.assign({}, notif)
        copy.timestamp = notif.timestamp.getTime() // Convert Date to milliseconds
        notifications.push(copy)
      }

      historyAdapter.notifications = notifications
      historyAdapter.lastSaved = Date.now()

      historyFileView.writeAdapter()

      Logger.log("Notifications", "Saved", notifications.length, "notifications to history")
    } catch (e) {
      Logger.error("Notifications", "Failed to save history:", e)
    }
  }

  // ===== Helper functions =====
  function resolveAppName(notification) {
    const appName = notification.appName || ""

    if (!appName.includes(".") || appName.length < 10) {
      return appName
    }

    // Try desktop entry lookup
    const desktopEntries = DesktopEntries.byId(appName)
    if (desktopEntries?.length > 0) {
      return desktopEntries[0].name || desktopEntries[0].genericName || appName
    }

    // Clean up reverse domain notation
    const parts = appName.split(".")
    if (parts.length > 1) {
      const lastPart = parts[parts.length - 1]
      return lastPart.charAt(0).toUpperCase() + lastPart.slice(1)
    }

    return appName
  }

  function resolveNotificationImage(notification) {
    const image = notification?.image || ""
    if (image) {
      return image
    }

    const icon = notification?.appIcon || ""
    if (!icon)
      return ""

    // Handle absolute paths and file URLs
    if (icon.startsWith("/"))
      return icon
    if (icon.startsWith("file://"))
      return icon.substring(7)

    // Resolve the icon
    return AppIcons.iconFromName(icon)
  }

  function formatTimestamp(timestamp) {
    if (!timestamp)
      return ""

    const diff = Date.now() - timestamp.getTime()

    if (diff < 60000)
      return "now"
    if (diff < 3600000)
      return `${Math.floor(diff / 60000)}m ago`
    if (diff < 86400000)
      return `${Math.floor(diff / 3600000)}h ago`
    return `${Math.floor(diff / 86400000)}d ago`
  }

  function strip_tags_regex(text) {
    return text.replace(/<[^>]*>?/gm, '')
  }

  // ===== Signals =====
  signal animateAndRemove(string notificationId, int index)

  // ===== Public API =====
  function dismissActiveNotification(notificationId) {
    dismissNotification(notificationId)
  }

  function dismissAllActive() {
    while (activeNotifications.count > 0) {
      const notif = activeNotifications.get(0)
      dismissNotification(notif.id)
    }
  }

  function invokeAction(notificationId, actionIdentifier) {
    const rawNotification = activeNotificationMap[notificationId]
    if (rawNotification && rawNotification.actions) {
      for (let action of rawNotification.actions) {
        if (action.identifier === actionIdentifier && action.invoke) {
          action.invoke()
          return true
        }
      }
    }
    return false
  }

  // ===== Do Not Disturb handler =====
  Connections {
    target: Settings.data.notifications
    function onDoNotDisturbChanged() {
      const enabled = Settings.data.notifications.doNotDisturb
      const label = enabled ? "'Do not disturb' enabled" : "'Do not disturb' disabled"
      const description = enabled ? "You'll find these notifications in your history." : "Showing all notifications."
      ToastService.showNotice(label, description)
    }
  }
}
