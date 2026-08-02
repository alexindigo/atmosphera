import QtQuick
import XdgIcon 1.0

Image {
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

  source: primary.path || fallback.path
  fillMode: Image.PreserveAspectFit
  smooth: true
  asynchronous: true
  sourceSize: Qt.size(root.pixelSize, root.pixelSize)
}
