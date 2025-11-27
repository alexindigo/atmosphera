import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons

Item {
  id: root

  property real radius: 0
  property string imagePath: ""
  property string fallbackIcon: ""
  property real fallbackIconSize: Style.fontSizeXXL
  property real borderWidth: 0
  property color borderColor: Color.transparent
  property int imageFillMode: Image.PreserveAspectCrop

  readonly property bool showFallback: (fallbackIcon !== undefined && fallbackIcon !== "") && (imagePath === undefined || imagePath === "")

  signal statusChanged(int status)

  // Use ClippingRectangle when visible, but switch to simple Rectangle when fading out
  // This prevents Qt 6.8 crashes with shaders in GridView delegates during close animations
  Loader {
    id: contentLoader
    anchors.fill: parent
    sourceComponent: root.opacity > 0.05 ? clippedContent : simpleContent
  }

  // Normal rendering with ClippingRectangle (uses shaders)
  Component {
    id: clippedContent

    ClippingRectangle {
      color: Color.transparent
      radius: root.radius
      border.color: root.borderColor
      border.width: root.borderWidth

      Image {
        anchors.fill: parent
        visible: !root.showFallback
        source: root.imagePath
        mipmap: true
        smooth: true
        asynchronous: true
        antialiasing: true
        fillMode: root.imageFillMode
        onStatusChanged: root.statusChanged(status)
      }

      NIcon {
        anchors.centerIn: parent
        visible: root.showFallback
        icon: root.fallbackIcon
        pointSize: root.fallbackIconSize
      }
    }
  }

  // Fallback rendering without shaders (when fading out)
  Component {
    id: simpleContent

    Rectangle {
      color: Color.transparent
      radius: root.radius
      border.color: root.borderColor
      border.width: root.borderWidth
      clip: true

      Image {
        anchors.fill: parent
        visible: !root.showFallback
        source: root.imagePath
        mipmap: true
        smooth: true
        asynchronous: true
        antialiasing: true
        fillMode: root.imageFillMode
        onStatusChanged: root.statusChanged(status)
      }

      NIcon {
        anchors.centerIn: parent
        visible: root.showFallback
        icon: root.fallbackIcon
        pointSize: root.fallbackIconSize
      }
    }
  }
}
