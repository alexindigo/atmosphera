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

  readonly property real scaling: ScalingService.getScreenScale(Quickshell.screens[0])
  readonly property real currentBrightness: {
    if (BrightnessService.monitors.length > 0) {
      return BrightnessService.monitors[0].brightness || 0
    }
    return 0
  }

  // Used to avoid showing OSD on Quickshell startup
  property bool firstBrightnessReceived: false

  function getIcon() {
    var brightness = currentBrightness
    return brightness <= 0.5 ? "brightness-low" : "brightness-high"
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
          color: Color.mOnSurface
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
              width: parent.width * windowLoader.currentBrightness
              radius: parent.radius
              color: Color.mPrimary

              Behavior on width {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCubic
                }
              }
            }
          }

          NText {
            text: Math.round(windowLoader.currentBrightness * 100) + "%"
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
    }

    function showOSD() {
      osdItem.show()
    }
  }

  // Monitor brightness changes from all monitors
  Connections {
    target: BrightnessService

    function onMonitorsChanged() {
      // Connect to brightness changes for each monitor
      for (var i = 0; i < BrightnessService.monitors.length; i++) {
        let monitor = BrightnessService.monitors[i]
        monitor.brightnessUpdated.connect(windowLoader.onBrightnessChanged)
      }
    }
  }

  // Connect to existing monitors on component completion
  Component.onCompleted: {
    for (var i = 0; i < BrightnessService.monitors.length; i++) {
      let monitor = BrightnessService.monitors[i]
      monitor.brightnessUpdated.connect(windowLoader.onBrightnessChanged)
    }
  }

  function onBrightnessChanged(newBrightness) {
    if (!firstBrightnessReceived) {
      // Ignore the first brightness change on startup
      firstBrightnessReceived = true
    } else {
      showOSD()
    }
  }

  // Signal to coordinate with other OSDs
  signal osdShowing

  function showOSD() {
    // Check if OSD is enabled in settings
    if (!Settings.data.general.showOSD) {
      return
    }

    osdShowing() // Notify other OSDs to hide
    windowLoader.active = true
    if (windowLoader.item) {
      windowLoader.item.showOSD()
    }
  }

  function hideOSD() {
    if (windowLoader.item) {
      windowLoader.item.osdItem.hideImmediately()
    }
  }
}
