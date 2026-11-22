import QtQuick
import XdgIcon 1.0
import qs.Commons
import qs.Widgets

// Theme lookup stays with XdgIcon; the resolved file is decoded by the shared
// image owner. A theme result that cannot be decoded falls back to
// fallbackName but stays a labelled failure, never an ordinary success.
Item {
  id: root

  property string name: ""
  property var size: 48
  property string fallbackName: "application-x-executable"

  readonly property int small: 32
  readonly property int medium: 48
  readonly property int large: 64
  readonly property int xlarge: 128

  readonly property int pixelSize: {
    var s = root.size;
    return (typeof s === "number" && s > 0) ? s : 48;
  }

  // Image-compatible outcome of what is actually presented.
  readonly property int status: image.status
  readonly property string source: image.source
  // A found theme icon whose bytes could not be decoded, even when the
  // fallback icon is presented in its place.
  readonly property bool failed: image.failed
  readonly property string errorCode: image.errorCode
  readonly property string errorReason: image.errorReason

  readonly property string _primaryPath: primary.path.toString()
  property var _failure: ({})
  readonly property bool _primaryRejected: _primaryPath !== "" && _failure.path === _primaryPath

  implicitWidth: pixelSize
  implicitHeight: pixelSize

  Accessible.role: Accessible.Graphic
  Accessible.description: failed ? errorReason : ""

  XdgIcon {
    id: primary
    name: root.name
    size: root.pixelSize
  }
  XdgIcon {
    id: fallback
    name: root.fallbackName
    size: root.pixelSize
  }

  NImageIcon {
    id: image
    anchors.fill: parent
    source: root._primaryPath && !root._primaryRejected ? root._primaryPath : fallback.path.toString()
    replacementCode: root._primaryRejected ? root._failure.code : ""
    replacementReason: root._primaryRejected ? root._failure.reason : ""
    sourceSize: Qt.size(root.pixelSize, root.pixelSize)
    smooth: root.smooth
    onImageStateChanged: {
      if (imageState !== "unavailable" || source !== root._primaryPath || !source)
        return;
      var path = source;
      // Read the settled failure and switch to the fallback after this state
      // notification, never inside it.
      Qt.callLater(() => {
        if (root._primaryPath !== path || image.source !== path || image.imageState !== "unavailable")
          return;
        Logger.w("AtmoAppIcon", "Icon", root.name, "could not be displayed:", image.errorReason);
        root._failure = {
          path: path,
          code: image.errorCode,
          reason: image.errorReason
        };
      });
    }
  }
}
