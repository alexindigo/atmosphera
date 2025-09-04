import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.SettingsPanel

NIconButton {
  id: root

  // Widget properties passed from Bar.qml
  property var screen
  property real scaling: 1.0

  property string barSection: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Get user settings from Settings data
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

  // Use settings or defaults from BarWidgetRegistry
  readonly property string userIcon: widgetSettings.icon || BarWidgetRegistry.widgetMetadata["CustomButton"].icon
  readonly property string userLeftClickExec: widgetSettings.leftClickExec
                                              || BarWidgetRegistry.widgetMetadata["CustomButton"].leftClickExec
  readonly property string userRightClickExec: widgetSettings.rightClickExec
                                               || BarWidgetRegistry.widgetMetadata["CustomButton"].rightClickExec
  readonly property string userMiddleClickExec: widgetSettings.middleClickExec
                                                || BarWidgetRegistry.widgetMetadata["CustomButton"].middleClickExec
  readonly property bool hasExec: (userLeftClickExec || userRightClickExec || userMiddleClickExec)

  icon: userIcon
  tooltipText: {
    if (!hasExec) {
      return "Custom Button - Configure in settings"
    } else {
      var lines = []
      if (userLeftClickExec !== "") {
        lines.push(`Left click: <i>${userLeftClickExec}</i>`)
      }
      if (userRightClickExec !== "") {
        lines.push(`Right click: <i>${userRightClickExec}</i>`)
      }
      if (userMiddleClickExec !== "") {
        lines.push(`Middle click: <i>${userMiddleClickExec}</i>`)
      }
      return lines.join("<br/>")
    }
  }
  opacity: hasExec ? Style.opacityFull : Style.opacityMedium

  onClicked: {
    if (userLeftClickExec) {
      Quickshell.execDetached(["sh", "-c", userLeftClickExec])
      Logger.log("CustomButton", `Executing command: ${userLeftClickExec}`)
    } else if (!hasExec) {
      // No script was defined, open settings
      var settingsPanel = PanelService.getPanel("settingsPanel")
      settingsPanel.requestedTab = SettingsPanel.Tab.Bar
      settingsPanel.open(screen)
    }
  }

  onRightClicked: {
    if (userRightClickExec) {
      Quickshell.execDetached(["sh", "-c", userRightClickExec])
      Logger.log("CustomButton", `Executing command: ${userRightClickExec}`)
    }
  }

  onMiddleClicked: {
    if (userMiddleClickExec) {
      Quickshell.execDetached(["sh", "-c", userMiddleClickExec])
      Logger.log("CustomButton", `Executing command: ${userMiddleClickExec}`)
    }
  }
}
