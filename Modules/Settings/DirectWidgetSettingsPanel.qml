import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Modules.Settings.Tabs
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: 0
  preferredHeight: 0
  panelBackgroundColor: Color.transparent
  panelBorderColor: Color.transparent

  property var requestedWidgetSettings: []

  panelContent: Item {

    Component.onCompleted: {
      Qt.callLater(() => {
                     var component = Qt.createComponent(Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Settings/Bar/BarWidgetSettingsDialog.qml"))

                     function instantiateAndOpen() {
                       var dialog = component.createObject(Overlay.overlay, {
                                                             "widgetIndex": requestedWidgetSettings.widgetIndex,
                                                             "widgetData": requestedWidgetSettings.widgetData,
                                                             "widgetId": requestedWidgetSettings.widgetId,
                                                             "sectionId": requestedWidgetSettings.sectionId
                                                           })
                       if (dialog) {
                         dialog.updateWidgetSettings.connect(updateWidgetSettingsInSection)
                         dialog.onClosed.connect(closeWidgetSettings)
                         dialog.open()
                       }
                     }

                     if (component.status === Component.Ready) {
                       instantiateAndOpen()
                     } else {
                       component.statusChanged.connect(instantiateAndOpen)
                     }

                     // Clear the request after handling
                     requestedWidgetSettings = []
                   })
    }
  }

  function openWidgetSettings(section, widgetIndex, widgetId, widgetData) {
    requestedWidgetSettings = {
      "sectionId": section,
      "widgetIndex": widgetIndex,
      "widgetId": widgetId,
      "widgetData": widgetData
    }
    root.open()
  }

  function updateWidgetSettingsInSection(section, index, settings) {
    Settings.data.bar.widgets[section][index] = settings
  }

  function closeWidgetSettings() {
    root.close()
  }
}
