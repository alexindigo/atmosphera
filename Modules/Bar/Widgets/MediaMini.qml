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
  Layout.preferredWidth: MediaService.currentPlayer !== null && MediaService.canPlay ? implicitWidth : 0

  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetSettings: {
    var section = barSection.replace("Section", "").toLowerCase()
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool userShowAlbumArt: (widgetSettings.showAlbumArt !== undefined) ? widgetSettings.showAlbumArt : ((Settings.data.audio.showMiniplayerAlbumArt !== undefined) ? Settings.data.audio.showMiniplayerAlbumArt : BarWidgetRegistry.widgetMetadata["MediaMini"].showAlbumArt)
  readonly property bool userShowVisualizer: (widgetSettings.showVisualizer !== undefined) ? widgetSettings.showVisualizer : ((Settings.data.audio.showMiniplayerCava !== undefined) ? Settings.data.audio.showMiniplayerCava : BarWidgetRegistry.widgetMetadata["MediaMini"].showVisualizer)
  readonly property string userVisualizerType: (widgetSettings.visualizerType !== undefined
                                                && widgetSettings.visualizerType
                                                !== "") ? widgetSettings.visualizerType : ((Settings.data.audio.visualizerType !== undefined
                                                                                            && Settings.data.audio.visualizerType !== "") ? Settings.data.audio.visualizerType : BarWidgetRegistry.widgetMetadata["MediaMini"].visualizerType)

  function getTitle() {
    return MediaService.trackTitle + (MediaService.trackArtist !== "" ? ` - ${MediaService.trackArtist}` : "")
  }

  //  A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
  }

  Rectangle {
    id: mediaMini

    Layout.preferredWidth: rowLayout.implicitWidth + Style.marginM * 2 * scaling
    Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
    Layout.alignment: Qt.AlignVCenter

    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    // Used to anchor the tooltip, so the tooltip does not move when the content expands
    Item {
      id: anchor
      height: parent.height
      width: 200 * scaling
    }

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: Style.marginS * scaling
      anchors.rightMargin: Style.marginS * scaling

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: userShowVisualizer && userVisualizerType == "linear" && MediaService.isPlaying
        z: 0

        sourceComponent: LinearSpectrum {
          width: mainContainer.width - Style.marginS * scaling
          height: 20 * scaling
          values: CavaService.values
          fillColor: Color.mOnSurfaceVariant
          opacity: 0.4
        }
      }

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: userShowVisualizer && userVisualizerType == "mirrored" && MediaService.isPlaying
        z: 0

        sourceComponent: MirroredSpectrum {
          width: mainContainer.width - Style.marginS * scaling
          height: mainContainer.height - Style.marginS * scaling
          values: CavaService.values
          fillColor: Color.mOnSurfaceVariant
          opacity: 0.4
        }
      }

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: userShowVisualizer && userVisualizerType == "wave" && MediaService.isPlaying
        z: 0

        sourceComponent: WaveSpectrum {
          width: mainContainer.width - Style.marginS * scaling
          height: mainContainer.height - Style.marginS * scaling
          values: CavaService.values
          fillColor: Color.mOnSurfaceVariant
          opacity: 0.4
        }
      }

      RowLayout {
        id: rowLayout
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling
        z: 1 // Above the visualizer

        NIcon {
          id: windowIcon
          text: MediaService.isPlaying ? "pause" : "play_arrow"
          font.pointSize: Style.fontSizeL * scaling
          verticalAlignment: Text.AlignVCenter
          Layout.alignment: Qt.AlignVCenter
          visible: !userShowAlbumArt && getTitle() !== "" && !trackArt.visible
        }

        ColumnLayout {
          Layout.alignment: Qt.AlignVCenter
          visible: userShowAlbumArt
          spacing: 0

          Item {
            Layout.preferredWidth: Math.round(18 * scaling)
            Layout.preferredHeight: Math.round(18 * scaling)

            NImageCircled {
              id: trackArt
              anchors.fill: parent
              imagePath: MediaService.trackArtUrl
              fallbackIcon: MediaService.isPlaying ? "pause" : "play_arrow"
              borderWidth: 0
              border.color: Color.transparent
            }
          }
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
          Layout.alignment: Qt.AlignVCenter

          text: getTitle()
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mTertiary

          Behavior on Layout.preferredWidth {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.InOutCubic
            }
          }
        }
      }

      // Mouse area for hover detection
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
                       // Need to hide the tooltip instantly
                       tooltip.visible = false
                     } else if (mouse.button == Qt.MiddleButton) {
                       MediaService.previous()
                       // Need to hide the tooltip instantly
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
  }

  Component.onCompleted: {
    try {
      var section = barSection.replace("Section", "").toLowerCase()
      if (section && sectionWidgetIndex >= 0) {
        var widgets = Settings.data.bar.widgets[section]
        if (widgets && sectionWidgetIndex < widgets.length) {
          var w = widgets[sectionWidgetIndex]
          if (w.showAlbumArt === undefined && Settings.data.audio.showMiniplayerAlbumArt !== undefined) {
            w.showAlbumArt = Settings.data.audio.showMiniplayerAlbumArt
          }
          if (w.showVisualizer === undefined && Settings.data.audio.showMiniplayerCava !== undefined) {
            w.showVisualizer = Settings.data.audio.showMiniplayerCava
          }
          if ((w.visualizerType === undefined || w.visualizerType === "")
              && (Settings.data.audio.visualizerType !== undefined && Settings.data.audio.visualizerType !== "")) {
            w.visualizerType = Settings.data.audio.visualizerType
          }
        }
      }
    } catch (e) {

    }
  }

  NTooltip {
    id: tooltip
    text: {
      var str = ""
      if (MediaService.canGoNext) {
        str += "Right click for next.\n"
      }
      if (MediaService.canGoPrevious) {
        str += "Middle click for previous."
      }
      return str
    }
    target: anchor
    positionAbove: Settings.data.bar.position === "bottom"
  }
}
