import QtQuick

Item {
  id: root

  property var pluginApi: null
  property var screen: null

  implicitWidth: 400
  implicitHeight: 300

  Component.onCompleted: console.log("FX " + JSON.stringify({ "id": "fx-instance", "entry": "panel", "phase": "completed", "label": pluginApi.pluginSettings.label }))
}
