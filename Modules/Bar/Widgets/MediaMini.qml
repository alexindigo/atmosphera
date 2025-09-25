import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.Audio
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool compact: (Settings.data.bar.density === "compact")

  readonly property bool showAlbumArt: (widgetSettings.showAlbumArt !== undefined) ? widgetSettings.showAlbumArt : widgetMetadata.showAlbumArt
  readonly property bool showVisualizer: (widgetSettings.showVisualizer !== undefined) ? widgetSettings.showVisualizer : widgetMetadata.showVisualizer
  readonly property string visualizerType: (widgetSettings.visualizerType !== undefined && widgetSettings.visualizerType !== "") ? widgetSettings.visualizerType : widgetMetadata.visualizerType
  readonly property string scrollingMode: (widgetSettings.scrollingMode !== undefined) ? widgetSettings.scrollingMode : widgetMetadata.scrollingMode

  // Fixed width - no expansion
  readonly property real widgetWidth: Math.max(1, screen.width * 0.06)

  function getTitle() {
    return MediaService.trackTitle + (MediaService.trackArtist !== "" ? ` - ${MediaService.trackArtist}` : "")
  }

  function calculatedVerticalHeight() {
    return Math.round(Style.baseWidgetSize * 0.8 * scaling)
  }

  implicitHeight: visible ? ((barPosition === "left" || barPosition === "right") ? calculatedVerticalHeight() : Math.round(Style.barHeight * scaling)) : 0
  implicitWidth: visible ? ((barPosition === "left" || barPosition === "right") ? Math.round(Style.baseWidgetSize * 0.8 * scaling) : (widgetWidth * scaling)) : 0

  visible: MediaService.currentPlayer !== null && MediaService.canPlay

  //  A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
  }

  Rectangle {
    id: mediaMini
    visible: root.visible
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: (barPosition === "left" || barPosition === "right") ? Math.round(Style.baseWidgetSize * 0.8 * scaling) : (widgetWidth * scaling)
    height: (barPosition === "left" || barPosition === "right") ? Math.round(Style.baseWidgetSize * 0.8 * scaling) : Math.round(Style.capsuleHeight * scaling)
    radius: (barPosition === "left" || barPosition === "right") ? width / 2 : Math.round(Style.radiusM * scaling)
    color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent



    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: (barPosition === "left" || barPosition === "right") ? 0 : Style.marginS * scaling
      anchors.rightMargin: (barPosition === "left" || barPosition === "right") ? 0 : Style.marginS * scaling

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: showVisualizer && visualizerType == "linear"
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
        active: showVisualizer && visualizerType == "mirrored"
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
        active: showVisualizer && visualizerType == "wave"
        z: 0

        sourceComponent: WaveSpectrum {
          width: mainContainer.width - Style.marginS * scaling
          height: mainContainer.height - Style.marginS * scaling
          values: CavaService.values
          fillColor: Color.mOnSurfaceVariant
          opacity: 0.4
        }
      }

      // Horizontal layout for top/bottom bars
      RowLayout {
        id: rowLayout
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling
        visible: barPosition === "top" || barPosition === "bottom"
        z: 1 // Above the visualizer

        NIcon {
          id: windowIcon
          icon: MediaService.isPlaying ? "media-pause" : "media-play"
          font.pointSize: Style.fontSizeL * scaling
          verticalAlignment: Text.AlignVCenter
          Layout.alignment: Qt.AlignVCenter
          visible: !showAlbumArt && getTitle() !== "" && !trackArt.visible
        }

        ColumnLayout {
          Layout.alignment: Qt.AlignVCenter
          visible: showAlbumArt
          spacing: 0

          Item {
            Layout.preferredWidth: Math.round(18 * scaling)
            Layout.preferredHeight: Math.round(18 * scaling)

            NImageCircled {
              id: trackArt
              anchors.fill: parent
              imagePath: MediaService.trackArtUrl
              fallbackIcon: MediaService.isPlaying ? "media-pause" : "media-play"
              fallbackIconSize: 10 * scaling
              borderWidth: 0
              border.color: Color.transparent
            }
          }
        }

        Item {
          id: titleContainer
          Layout.preferredWidth: {
            // Calculate available width based on other elements in the row
            var iconWidth = (windowIcon.visible ? (Style.fontSizeL * scaling + Style.marginS * scaling) : 0)
            var albumArtWidth = (showAlbumArt ? (18 * scaling + Style.marginS * scaling) : 0)
            var totalMargins = Style.marginXXS * scaling * 2
            var availableWidth = mainContainer.width - iconWidth - albumArtWidth - totalMargins
            return Math.max(20 * scaling, availableWidth) // Ensure minimum width
          }
          Layout.maximumWidth: Layout.preferredWidth // Constrain maximum width
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredHeight: titleText.height

          clip: true // This is already set, but crucial for preventing overflow

          property bool isScrolling: false
          property bool isResetting: false

          // Timer for "always" mode with delay
          Timer {
            id: scrollStartTimer
            interval: 2000 // Wait 2 seconds before starting scroll
            repeat: false
            onTriggered: {
              if (scrollingMode === "always" && fullTitleMetrics.contentWidth > titleContainer.width) {
                titleContainer.isScrolling = true
                titleContainer.isResetting = false
              }
            }
          }

          // Update scrolling state based on mode - using property instead of function
          property var updateScrollingState: function () {
            if (scrollingMode === "never") {
              isScrolling = false
              isResetting = false
            } else if (scrollingMode === "always") {
              if (fullTitleMetrics.contentWidth > titleContainer.width) {
                if (mouseArea.containsMouse) {
                  // Mouse entered - stop scrolling and reset
                  isScrolling = false
                  isResetting = true
                } else {
                  // Mouse not hovering - start scroll after delay
                  scrollStartTimer.restart()
                }
              } else {
                scrollStartTimer.stop()
                isScrolling = false
                isResetting = false
              }
            } else if (scrollingMode === "hover") {
              if (mouseArea.containsMouse && fullTitleMetrics.contentWidth > titleContainer.width) {
                isScrolling = true
                isResetting = false
              } else {
                // Stop scrolling and reset when not hovering
                isScrolling = false
                if (fullTitleMetrics.contentWidth > titleContainer.width) {
                  isResetting = true
                }
              }
            }
          }

          // React to text changes
          onWidthChanged: updateScrollingState()
          Component.onCompleted: updateScrollingState()

          // React to hover changes from the main mouse area
          Connections {
            target: mouseArea
            function onContainsMouseChanged() {
              titleContainer.updateScrollingState()
            }
          }

          Item {
            anchors.fill: parent
            clip: true

            NText {
              id: titleText

              text: getTitle()
              font.pointSize: Style.fontSizeS * scaling
              font.weight: Style.fontWeightMedium
              verticalAlignment: Text.AlignVCenter
              color: Color.mOnSurface

              property real scrollPosition: 0

              x: scrollPosition

              // Reset animation when mouse exits
              NumberAnimation on scrollPosition {
                id: resetAnimation
                running: titleContainer.isResetting
                to: 0
                duration: 300
                easing.type: Easing.OutQuad
                onFinished: {
                  titleContainer.isResetting = false
                }
              }

              // Continuous scrolling animation
              SequentialAnimation on scrollPosition {
                running: titleContainer.isScrolling && !titleContainer.isResetting
                loops: Animation.Infinite

                // Reset position at start of each loop
                PropertyAction {
                  target: titleText
                  property: "scrollPosition"
                  value: 0
                }

                PauseAnimation {
                  duration: 1000
                }

                NumberAnimation {
                  from: 0
                  to: -(fullTitleMetrics.contentWidth - titleContainer.width + 10 * scaling)
                  duration: Math.max(3000, getTitle().length * 100)
                  easing.type: Easing.Linear
                }

                // Add pause at the end before looping
                PauseAnimation {
                  duration: 1000
                }
              }
            }
          }

          Behavior on Layout.preferredWidth {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.InOutCubic
            }
          }
        }
      }

      // Vertical layout for left/right bars - icon only
      Item {
        id: verticalLayout
        anchors.centerIn: parent
        width: parent.width - Style.marginM * scaling * 2
        height: parent.height - Style.marginM * scaling * 2
        visible: barPosition === "left" || barPosition === "right"
        z: 1 // Above the visualizer

        // Media icon
        Item {
          width: Style.baseWidgetSize * 0.5 * scaling
          height: Style.baseWidgetSize * 0.5 * scaling
          anchors.centerIn: parent
          visible: getTitle() !== ""

          NIcon {
            id: mediaIconVertical
            anchors.fill: parent
            icon: MediaService.isPlaying ? "media-pause" : "media-play"
            font.pointSize: Style.fontSizeL * scaling
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
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
          if (scrollingMode !== "never") return
          if (barPosition === "left" || barPosition === "right") {
            tooltip.show()
          } else if (tooltip.text !== "") {
            tooltip.show()
          }
        }
        onExited: {
          if (scrollingMode !== "never") return
          if (barPosition === "left" || barPosition === "right") {
            tooltip.hide()
          } else {
            tooltip.hide()
          }
        }
      }
    }
  }

  NTooltip {
    id: tooltip
    text: {
      var title = getTitle()
      var controls = ""
      if (MediaService.canGoNext) {
        controls += "Right click for next.\n"
      }
      if (MediaService.canGoPrevious) {
        controls += "Middle click for previous."
      }
      if (controls !== "") {
        return title + "\n\n" + controls
      }
      return title
    }
    target: (barPosition === "left" || barPosition === "right") ? verticalLayout : mediaMini
    positionLeft: barPosition === "right"
    positionRight: barPosition === "left"
    positionAbove: Settings.data.bar.position === "bottom"
    delay: Style.tooltipDelayLong
  }
}