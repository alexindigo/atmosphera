import QtQuick
import QtQuick.Window
import XdgIcon 1.0
import qs.Widgets

// Popup and history receive the same retained-image record. Original producer
// URLs are identity only and must never be renderer fallbacks.
NImageRounded {
  id: root
  property var notification: ({})
  imagePath: notification.cachedImage || (notification.imageState === "idle" ? appIcon.path : "")
  sourceRevision: notification.imageRevision || ""
  sourceFailureCode: notification.imageState === "unavailable" ? notification.imageErrorCode || "image-unavailable" : ""
  sourceFailureReason: notification.imageErrorReason || ""
  animationIntent: "still"
  fallbackIcon: "bell"
  borderWidth: 0
  borderColor: "transparent"

  XdgIcon {
    id: appIcon
    name: root.notification.iconName || ""
    size: Math.max(1, Math.ceil(root.width * Screen.devicePixelRatio))
  }
}
