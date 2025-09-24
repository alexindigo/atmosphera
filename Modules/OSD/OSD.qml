import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Loader {
  id: windowLoader
  active: false

  // OSD Type enum
  enum Type {
    Volume,
    Brightness
  }

  property int osdType: OSD.Type.Volume
  readonly property real scaling: ScalingService.getScreenScale(Quickshell.screens[0])

  // Volume properties
  readonly property real currentVolume: AudioService.volume
  readonly property bool isMuted: AudioService.muted
  property bool firstVolumeReceived: false
  property bool firstMuteReceived: false

  // Brightness properties
  readonly property real currentBrightness: {
    if (BrightnessService.monitors.length > 0) {
      return BrightnessService.monitors[0].brightness || 0
    }
    return 0
  }
  property bool firstBrightnessReceived: false

  // Get appropriate icon based on OSD type
  function getIcon() {
    if (osdType === OSD.Type.Volume) {
      if (AudioService.muted) {
        return "volume-mute"
      }
      return (AudioService.volume <= Number.EPSILON) ? "volume-zero" : (AudioService.volume <= 0.5) ? "volume-low" : "volume-high"
    } else {
      // Brightness
      var brightness = currentBrightness
      return brightness <= 0.5 ? "brightness-low" : "brightness-high"
    }
  }

  // Get current value (0-1 range)
  function getCurrentValue() {
    if (osdType === OSD.Type.Volume) {
      return isMuted ? 0 : currentVolume
    } else {
      return currentBrightness
    }
  }

  // Get display percentage
  function getDisplayPercentage() {
    if (osdType === OSD.Type.Volume) {
      return isMuted ? "0%" : Math.round(currentVolume * 100) + "%"
    } else {
      return Math.round(currentBrightness * 100) + "%"
    }
  }

  // Get progress bar color
  function getProgressColor() {
    if (osdType === OSD.Type.Volume) {
      if (isMuted)
        return Color.mError
      if (currentVolume > 1.0)
        return Color.mError
      return Color.mPrimary
    } else {
      return Color.mPrimary
    }
  }

  // Get icon color
  function getIconColor() {
    if (osdType === OSD.Type.Volume) {
      return isMuted ? Color.mError : Color.mOnSurface
    } else {
      return Color.mOnSurface
    }
  }

  sourceComponent: PanelWindow {
    id: panel

    screen: Quickshell.screens[0] // Use primary screen

    anchors {
      top: true
    }

    implicitWidth: 320 * windowLoader.scaling
    implicitHeight: osdItem.height

    // Set margins based on bar position
    margins.top: {
      switch (Settings.data.bar.position) {
      case "top":
        return (Style.barHeight + Style.marginS) * windowLoader.scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * windowLoader.scaling : 0)
      default:
        return Style.marginL * windowLoader.scaling
      }
    }

    color: Color.transparent

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: PanelWindow.ExclusionMode.Ignore

    Rectangle {
      id: osdItem

      width: parent.width
      height: Math.round(contentLayout.implicitHeight + Style.marginL * 2 * windowLoader.scaling)
      radius: Style.radiusL * windowLoader.scaling
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: Math.max(2, Style.borderM * windowLoader.scaling)
      visible: false
      opacity: 0
      scale: 0.7

      anchors.horizontalCenter: parent.horizontalCenter

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }

      Behavior on scale {
        NumberAnimation {
          duration: Style.animationFast
          easing.type: Easing.OutCubic
        }
      }

      Timer {
        id: hideTimer
        interval: 2000
        onTriggered: osdItem.hide()
      }

      RowLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Style.marginM * windowLoader.scaling
        spacing: Style.marginM * windowLoader.scaling

        NIcon {
          icon: windowLoader.getIcon()
          color: windowLoader.getIconColor()
          font.pointSize: Style.fontSizeXL * windowLoader.scaling
          Layout.alignment: Qt.AlignVCenter
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.marginXS * windowLoader.scaling

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(6 * windowLoader.scaling)
            radius: Math.round(3 * windowLoader.scaling)
            color: Color.mSurfaceVariant

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * Math.min(1.0, windowLoader.getCurrentValue())
              radius: parent.radius
              color: windowLoader.getProgressColor()

              Behavior on width {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCubic
                }
              }

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }

          NText {
            text: windowLoader.getDisplayPercentage()
            color: Color.mOnSurfaceVariant
            font.pointSize: Style.fontSizeS * windowLoader.scaling
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: Math.round(32 * windowLoader.scaling)
          }
        }
      }

      function show() {
        hideTimer.stop()
        osdItem.visible = true
        osdItem.opacity = 1
        osdItem.scale = 1.0
        hideTimer.start()
      }

      function hide() {
        hideTimer.stop()
        osdItem.opacity = 0
        osdItem.scale = 0.7

        Qt.callLater(function () {
          osdItem.visible = false
          windowLoader.active = false
        })
      }

      function hideImmediately() {
        hideTimer.stop()
        osdItem.opacity = 0
        osdItem.scale = 0.7
        osdItem.visible = false
        windowLoader.active = false
      }
    }

    function showOSD() {
      osdItem.show()
    }
  }

  // Volume change monitoring
  Connections {
    target: AudioService
    enabled: osdType === OSD.Type.Volume

    function onVolumeChanged() {
      if (!firstVolumeReceived) {
        firstVolumeReceived = true
      } else {
        showOSD()
      }
    }

    function onMutedChanged() {
      if (!firstMuteReceived) {
        firstMuteReceived = true
      } else {
        showOSD()
      }
    }
  }

  // Brightness change monitoring
  Connections {
    target: BrightnessService
    enabled: osdType === OSD.Type.Brightness

    function onMonitorsChanged() {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        let monitor = BrightnessService.monitors[i]
        monitor.brightnessUpdated.connect(windowLoader.onBrightnessChanged)
      }
    }
  }

  Component.onCompleted: {
    if (osdType === OSD.Type.Brightness) {
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        let monitor = BrightnessService.monitors[i]
        monitor.brightnessUpdated.connect(windowLoader.onBrightnessChanged)
      }
    }
  }

  function onBrightnessChanged(newBrightness) {
    if (!firstBrightnessReceived) {
      firstBrightnessReceived = true
    } else {
      showOSD()
    }
  }

  // Signal to coordinate with other OSDs
  signal osdShowing

  function showOSD() {
    // Check if OSD is enabled in settings
    if (!Settings.data.notifications.enableOSD) {
      return
    }

    osdShowing() // Notify other OSDs to hide
    windowLoader.active = true
    if (windowLoader.item) {
      windowLoader.item.showOSD()
    }
  }

  function hideOSD() {
    if (windowLoader.item && windowLoader.item.osdItem) {
      windowLoader.item.osdItem.hideImmediately()
    } else if (windowLoader.active) {
      // If window exists but osdItem isn't ready, just deactivate the loader
      windowLoader.active = false
    }
  }
}
