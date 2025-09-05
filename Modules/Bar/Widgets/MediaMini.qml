import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.Audio
import qs.Commons
import qs.Services
import qs.Widgets

RowLayout {
  id: root

  property ShellScreen screen
  property real scaling: 1.0
  readonly property real minWidth: 160
  readonly property real maxWidth: 400

  Layout.alignment: Qt.AlignVCenter
  spacing: Style.marginS * scaling
  visible: MediaService.currentPlayer !== null && MediaService.canPlay
  width: MediaService.currentPlayer !== null && MediaService.canPlay ? implicitWidth : 0

  function getTitle() {
    return MediaService.trackTitle + (MediaService.trackArtist !== "" ? ` - ${MediaService.trackArtist}` : "")
  }

  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
  }

  Rectangle {
    id: mediaMini
    width: contentLayout.implicitWidth + Style.marginS * 2 * scaling
    height: Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant
    Layout.alignment: Qt.AlignVCenter

    // --- Visualizer Loaders ---
    Loader {
      anchors.centerIn: parent
      active: Settings.data.audio.showMiniplayerCava && Settings.data.audio.visualizerType == "linear"
              && MediaService.isPlaying && MediaService.trackLength > 0
      z: 0
      sourceComponent: LinearSpectrum {
        width: mediaMini.width - Style.marginS * scaling
        height: 20 * scaling
        values: CavaService.values
        fillColor: Color.mOnSurfaceVariant
        opacity: 0.4
      }
    }

    Loader {
      anchors.centerIn: parent
      active: Settings.data.audio.showMiniplayerCava && Settings.data.audio.visualizerType == "mirrored"
              && MediaService.isPlaying && MediaService.trackLength > 0
      z: 0
      sourceComponent: MirroredSpectrum {
        width: mediaMini.width - Style.marginS * scaling
        height: mediaMini.height - Style.marginS * scaling
        values: CavaService.values
        fillColor: Color.mOnSurfaceVariant
        opacity: 0.4
      }
    }

    Loader {
      anchors.centerIn: parent
      active: Settings.data.audio.showMiniplayerCava && Settings.data.audio.visualizerType == "wave"
              && MediaService.isPlaying && MediaService.trackLength > 0
      z: 0
      sourceComponent: WaveSpectrum {
        width: mediaMini.width - Style.marginS * scaling
        height: mediaMini.height - Style.marginS * scaling
        values: CavaService.values
        fillColor: Color.mOnSurfaceVariant
        opacity: 0.4
      }
    }

    // --- Main Content Layout ---
    RowLayout {
      id: contentLayout
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.marginS * scaling
      spacing: Style.marginS * scaling
      z: 1

      NIcon {
        id: windowIcon
        text: MediaService.isPlaying ? "pause" : "play_arrow"
        font.pointSize: Style.fontSizeL * scaling
        Layout.alignment: Qt.AlignVCenter
        visible: !Settings.data.audio.showMiniplayerAlbumArt && getTitle() !== "" && !trackArt.visible
      }

      NImageCircled {
        id: trackArt
        imagePath: MediaService.trackArtUrl
        fallbackIcon: MediaService.isPlaying ? "pause" : "play_arrow"
        borderWidth: 0
        border.color: Color.transparent
        Layout.preferredWidth: Math.round(18 * scaling)
        Layout.preferredHeight: Math.round(18 * scaling)
        Layout.alignment: Qt.AlignVCenter
        visible: Settings.data.audio.showMiniplayerAlbumArt
      }

      NText {
        id: titleText
        Layout.preferredWidth: {
          if (mouseArea.containsMouse) {
            return Math.round(Math.min(fullTitleMetrics.contentWidth, root.maxWidth * scaling))
          } else {
            return Math.round(Math.min(fullTitleMetrics.contentWidth, root.minWidth * scaling))
          }
        }
        text: getTitle()
        font.pointSize: Style.fontSizeS * scaling
        font.weight: Style.fontWeightMedium
        elide: Text.ElideRight
        color: Color.mTertiary
        Layout.alignment: Qt.AlignVCenter

        Behavior on Layout.preferredWidth {
          NumberAnimation {
            duration: Style.animationSlow
            easing.type: Easing.InOutCubic
          }
        }
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: mouse => {
                   if (mouse.button === Qt.LeftButton) {
                     MediaService.playPause()
                   } else if (mouse.button == Qt.RightButton) {
                     MediaService.next()
                     tooltip.visible = false
                   } else if (mouse.button == Qt.MiddleButton) {
                     MediaService.previous()
                     tooltip.visible = false
                   }
                 }
      onEntered: {
        if (tooltip.text !== "") {
          tooltip.show()
        }
      }
      onExited: {
        tooltip.hide()
      }
    }
  }

  NTooltip {
    id: tooltip
    text: {
      var str = ""
      if (MediaService.canGoNext) {
        str += "Right click for next\n"
      }
      if (MediaService.canGoPrevious) {
        str += "Middle click for previous\n"
      }
      return str
    }
    target: mediaMini
    positionAbove: Settings.data.bar.position === "bottom"
  }
}
