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

  readonly property bool showFallback: (fallbackIcon !== undefined && fallbackIcon !== "") && (imagePath === undefined || imagePath === "")

  signal statusChanged(int status)

  ClippingWrapperRectangle {
    anchors.fill: parent
    color: Color.transparent
    radius: root.radius
    border.color: root.borderColor
    border.width: root.borderWidth

    Item {
      anchors.fill: parent
      Loader {
        active: true
        anchors.fill: parent
        sourceComponent: showFallback ? fallback : image
      }

      Component {
        id: image
        Image {
          source: imagePath
          mipmap: true
          smooth: true
          asynchronous: true
          antialiasing: true
          fillMode: Image.PreserveAspectCrop
          onStatusChanged: root.statusChanged(status)
        }
      }

      Component {
        id: fallback
        NIcon {
          anchors.centerIn: parent
          icon: fallbackIcon
          pointSize: fallbackIconSize
        }
      }
    }
  }
}
