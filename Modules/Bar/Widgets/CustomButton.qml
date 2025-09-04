import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

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
  property string userIcon: widgetSettings.icon || BarWidgetRegistry.widgetMetadata["CustomButton"].icon
  property string userExecute: widgetSettings.execute || BarWidgetRegistry.widgetMetadata["CustomButton"].execute
  
  icon: userIcon
  tooltipText: userExecute ? `Execute: ${userExecute}` : "Custom Button - Configure in settings"
  
  colorBg: Color.transparent
  colorFg: Color.mOnSurface
  colorBgHover: Color.applyOpacity(Color.mPrimary, "20")
  colorFgHover: Color.mPrimary
  
  onClicked: {
    if (userExecute) {
      // Execute the user's command
      Quickshell.execDetached(userExecute.split(" "))
      Logger.log("CustomButton", `Executing command: ${userExecute}`)
    } else {
      Logger.warn("CustomButton", "No command configured for this button")
    }
  }
  
  // Visual feedback when no command is set
  opacity: userExecute ? 1.0 : 0.6
  
  Component.onCompleted: {
    Logger.log("CustomButton", `Initialized with icon: ${userIcon}, command: ${userExecute}`)
  }
}