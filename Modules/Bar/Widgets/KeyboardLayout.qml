import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Use the shared service for keyboard layout
  property string currentLayout: KeyboardLayoutService.currentLayout

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPill {
    id: pill

    anchors.verticalCenter: parent.verticalCenter
    rightOpen: BarWidgetRegistry.getNPillDirection(root)
    icon: "keyboard"
    autoHide: false // Important to be false so we can hover as long as we want
    text: currentLayout
    tooltipText: "Keyboard layout: " + currentLayout

    onClicked: {

      // You could open keyboard settings here if needed
      // For now, just show the current layout
    }
  }
}
