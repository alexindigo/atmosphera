import QtQuick
import qs.Commons

QtObject {
  id: root

  // Signal emitted when widget loading status changes
  signal widgetLoaded(string widgetName)
  signal widgetFailed(string widgetName, string error)
  signal loadingComplete(int total, int loaded, int failed)

  // Properties to track loading status
  property int totalWidgets: 0
  property int loadedWidgets: 0
  property int failedWidgets: 0

  // Auto-discover widget components
  function getWidgetComponent(widgetName) {
    if (!widgetName || widgetName.trim() === "") {
      return null
    }
    
    const widgetPath = `../Modules/Bar/Widgets/${widgetName}.qml`
    Logger.log("WidgetLoader", `Attempting to load widget from: ${widgetPath}`)
    
    // Try to load the widget directly from file
    const component = Qt.createComponent(widgetPath)
    if (component.status === Component.Ready) {
      Logger.log("WidgetLoader", `Successfully created component for: ${widgetName}.qml`)
      return component
    }
    
    const errorMsg = `Failed to load ${widgetName}.qml widget, status: ${component.status}, error: ${component.errorString()}`
    Logger.error("WidgetLoader", errorMsg)
    return null
  }

  // Initialize loading tracking
  function initializeLoading(widgetList) {
    totalWidgets = widgetList.length
    loadedWidgets = 0
    failedWidgets = 0
    
    if (totalWidgets > 0) {
      Logger.log("WidgetLoader", `Attempting to load ${totalWidgets} widgets`)
    }
  }

  // Track widget loading success
  function onWidgetLoaded(widgetName) {
    loadedWidgets++
    widgetLoaded(widgetName)
    
    if (loadedWidgets + failedWidgets === totalWidgets) {
      Logger.log("WidgetLoader", `Loaded ${loadedWidgets}/${totalWidgets} widgets`)
      loadingComplete(totalWidgets, loadedWidgets, failedWidgets)
    }
  }

  // Track widget loading failure
  function onWidgetFailed(widgetName, error) {
    failedWidgets++
    widgetFailed(widgetName, error)
    
    if (loadedWidgets + failedWidgets === totalWidgets) {
      Logger.log("WidgetLoader", `Loaded ${loadedWidgets}/${totalWidgets} widgets`)
      loadingComplete(totalWidgets, loadedWidgets, failedWidgets)
    }
  }
}
