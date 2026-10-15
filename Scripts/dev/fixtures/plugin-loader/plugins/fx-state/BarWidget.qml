import QtQuick

Item {
  id: root

  property var pluginApi: null
  property var screen: null
  property int sectionWidgetIndex: -1

  implicitWidth: 40
  implicitHeight: 24

  Component.onCompleted: console.log("FX " + JSON.stringify({ "id": "fx-state", "entry": "barWidget", "phase": "completed", "index": sectionWidgetIndex, "starts": pluginApi.state.starts }))
}
