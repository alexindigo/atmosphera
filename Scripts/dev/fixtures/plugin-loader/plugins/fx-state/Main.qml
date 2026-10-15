import QtQuick

Item {
  id: root

  property var pluginApi: null

  // One increment per shell start, saved to the shared plugin state.
  Component.onCompleted: {
    pluginApi.state.starts = (pluginApi.state.starts || 0) + 1;
    pluginApi.saveState();
    console.log("FX " + JSON.stringify({ "id": "fx-state", "entry": "main", "phase": "completed", "starts": pluginApi.state.starts }));
  }
}
