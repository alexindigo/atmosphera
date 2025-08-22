import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Notification

Variants {
  model: Quickshell.screens

  delegate: PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property real scaling: ScalingService.scale(screen)
    screen: modelData

    WlrLayershell.namespace: "noctalia-bar"

    implicitHeight: Style.barHeight * scaling
    color: Color.transparent

    Component.onCompleted: {
      logWidgetLoadingSummary()
    }

    // If no bar activated in settings, then show them all
    visible: modelData ? (Settings.data.bar.monitors.includes(modelData.name)
                          || (Settings.data.bar.monitors.length === 0)) : false

    anchors {
      top: Settings.data.bar.position === "top"
      bottom: Settings.data.bar.position === "bottom"
      left: true
      right: true
    }

    Item {
      anchors.fill: parent
      clip: true

      // Background fill
      Rectangle {
        id: bar

        anchors.fill: parent
        color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, Settings.data.bar.backgroundOpacity)
        layer.enabled: true
      }

      // Left Section - Dynamic Widgets
      Row {
        id: leftSection

        height: parent.height
        anchors.left: parent.left
        anchors.leftMargin: Style.marginS * scaling
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling

        Repeater {
          model: Settings.data.bar.widgets.left
          delegate: Loader {
            id: widgetLoader
            sourceComponent: getWidgetComponent(modelData)
            active: true
            anchors.verticalCenter: parent.verticalCenter
            onStatusChanged: {
              if (status === Loader.Error) {
                Logger.error("Bar", `Failed to load ${modelData} widget`)
                onWidgetFailed()
              } else if (status === Loader.Ready) {
                onWidgetLoaded()
              }
            }
          }
        }
      }

      // Center Section - Dynamic Widgets
      Row {
        id: centerSection

        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling

        Repeater {
          model: Settings.data.bar.widgets.center
          delegate: Loader {
            id: widgetLoader
            sourceComponent: getWidgetComponent(modelData)
            active: true
            anchors.verticalCenter: parent.verticalCenter
            onStatusChanged: {
              if (status === Loader.Error) {
                Logger.error("Bar", `Failed to load ${modelData} widget`)
                onWidgetFailed()
              } else if (status === Loader.Ready) {
                onWidgetLoaded()
              }
            }
          }
        }
      }

      // Right Section - Dynamic Widgets
      Row {
        id: rightSection

        height: parent.height
        anchors.right: bar.right
        anchors.rightMargin: Style.marginS * scaling
        anchors.verticalCenter: bar.verticalCenter
        spacing: Style.marginS * scaling

        Repeater {
          model: Settings.data.bar.widgets.right
          delegate: Loader {
            id: widgetLoader
            sourceComponent: getWidgetComponent(modelData)
            active: true
            anchors.verticalCenter: parent.verticalCenter
            onStatusChanged: {
              if (status === Loader.Error) {
                Logger.error("Bar", `Failed to load ${modelData} widget`)
                onWidgetFailed()
              } else if (status === Loader.Ready) {
                onWidgetLoaded()
              }
            }
          }
        }
      }
    }

    // Auto-discover widget components
    function getWidgetComponent(widgetName) {
      if (!widgetName || widgetName.trim() === "") {
        return null
      }
      
      const widgetPath = `../Bar/Widgets/${widgetName}.qml`
      Logger.log("Bar", `Attempting to load widget from: ${widgetPath}`)
      
      // Try to load the widget directly from file
      const component = Qt.createComponent(widgetPath)
      if (component.status === Component.Ready) {
        Logger.log("Bar", `Successfully created component for: ${widgetName}.qml`)
        return component
      }
      
      Logger.error("Bar", `Failed to load ${widgetName}.qml widget, status: ${component.status}, error: ${component.errorString()}`)
      return null
    }

    // Track widget loading status
    property int totalWidgets: 0
    property int loadedWidgets: 0
    property int failedWidgets: 0

    // Log widget loading summary
    function logWidgetLoadingSummary() {
      const allWidgets = [
        ...Settings.data.bar.widgets.left,
        ...Settings.data.bar.widgets.center,
        ...Settings.data.bar.widgets.right
      ]
      
      totalWidgets = allWidgets.length
      loadedWidgets = 0
      failedWidgets = 0
      
      if (totalWidgets > 0) {
        Logger.log("Bar", `Attempting to load ${totalWidgets} widgets`)
      }
    }

    function onWidgetLoaded() {
      loadedWidgets++
      if (loadedWidgets + failedWidgets === totalWidgets) {
        Logger.log("Bar", `Loaded ${loadedWidgets}/${totalWidgets} widgets`)
      }
    }

    function onWidgetFailed() {
      failedWidgets++
      if (loadedWidgets + failedWidgets === totalWidgets) {
        Logger.log("Bar", `Loaded ${loadedWidgets}/${totalWidgets} widgets`)
      }
    }




  }
}
