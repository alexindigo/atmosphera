import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Dummy comment to force re-evaluation
Item {
  id: root

  // Widget properties
  property string widgetId: "CustomButton"
  property var widgetSettings: {} // This will be populated from settings

  // Use settings or provide defaults
  readonly property string customIcon: widgetSettings.icon || "heart"
  readonly property string exec: widgetSettings.exec || ""
  readonly property string tooltipText: widgetSettings.tooltipText || "Custom Button"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  NIconButton {
    id: button
    icon: customIcon
    tooltipText: tooltipText
    onClicked: {
      if (exec) {
        Quickshell.execDetached(["sh", "-c", exec])
        Logger.i("CC:CustomButton", `Executing command: ${exec}`)
      }
    }
  }
}
