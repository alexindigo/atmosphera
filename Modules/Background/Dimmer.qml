import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Variants {
  model: Quickshell.screens

  delegate: Loader {
    required property ShellScreen modelData

    // Dimmer is only active on the screen where the panel is currently open.
    active: {
      if (Settings.isLoaded && Settings.data.general.dimDesktop && modelData !== undefined && PanelService.openedPanel !== null && PanelService.openedPanel.item !== undefined && PanelService.openedPanel.item !== null) {
        return (PanelService.openedPanel.item.screen === modelData)
      }

      return false
    }

    sourceComponent: PanelWindow {
      id: panel

      property real customOpacity: 0

      Component.onCompleted: {
        if (modelData) {
          Logger.log("Dimmer", "Loaded on", modelData.name)
        }

        // When a NPanel opens it seems it is initialized with the primary screen for a very brief moment
        // before the screen actually updates to the proper value. We use a timer to delay the fade in to avoid
        // a single frame flicker on the main screen when opening a panel on another screen.
        fadeInTimer.start()
      }

      Connections {
        target: PanelService
        function onWillClose() {
          customOpacity = Style.opacityNone
        }
      }

      Timer {
        id: fadeInTimer
        interval: 100
        onTriggered: customOpacity = Style.opacityHeavy
      }

      screen: modelData

      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "quickshell-dimmer"

      // mask: Region {}
      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }

      color: Qt.alpha(Color.mShadow, customOpacity)
      Behavior on color {
        ColorAnimation {
          duration: Style.animationSlow
        }
      }
    }
  }
}
