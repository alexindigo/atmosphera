import QtQuick
import Quickshell.Io
Item {
  property var pluginApi: null
  IpcHandler {
    target: "plugin:fx-bad"
    function show() {}
  }
}
