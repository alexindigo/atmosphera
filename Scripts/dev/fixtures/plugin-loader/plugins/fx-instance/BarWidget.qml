import QtQuick

Item {
  id: root

  property var pluginApi: null
  property var screen: null
  property int sectionWidgetIndex: -1

  implicitWidth: 40
  implicitHeight: 24

  // Startup behaviour is read from the effective settings of this instance:
  // saveOnLoad writes counter once; openOnLoad opens the panel once.
  Component.onCompleted: {
    var settings = pluginApi.pluginSettings;
    console.log("FX " + JSON.stringify({ "id": "fx-instance", "entry": "barWidget", "phase": "completed", "index": sectionWidgetIndex, "label": settings.label }));
    if (settings.saveOnLoad === true && settings.counter !== 1) {
      settings.counter = 1;
      pluginApi.saveSettings();
    }
    if (settings.openOnLoad === true && !pluginApi.panelOpenScreen)
      pluginApi.openPanel(screen, root);
  }
}
