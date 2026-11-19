// Inert actual registry URL/import witness; component construction is separate.
import QtQuick
import Quickshell
import qs.Services.UI

Scope {
  function checkMap(map, directory) {
    Object.keys(map).forEach(function (id) {
      var path = Quickshell.shellDir + directory + map[id];
      var component = Qt.createComponent(path);
      if (component.status !== Component.Ready)
        throw new Error("I4_PAGE_LINK_ASSERT: " + id + ": " + component.errorString());
      component.destroy();
    });
  }
  Component.onCompleted: Qt.callLater(function () {
    try {
      checkMap(BarWidgetRegistry.widgetSettingsMap, "/Modules/Panels/Settings/Bar/");
      checkMap(DesktopWidgetRegistry.widgetSettingsMap, "/Modules/Panels/Settings/DesktopWidgets/");
      console.log("I4_WIDGET_PAGE_LINKS: PASS");
      Qt.exit(0);
    } catch (error) {
      console.error(String(error));
      Qt.exit(2);
    }
  })
}
