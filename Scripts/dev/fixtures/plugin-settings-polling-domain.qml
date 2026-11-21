// Actual Main/Timer type policy with explicit test input, not instance acceptance.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: root
  property var main: null
  property int ticks: 0
  FileView {
    id: manifest
    path: Quickshell.env("POLL_EDGE_CASE") + "/manifest.json"
    blockLoading: true
  }
  function find(object) {
    if (object && object.repeat === true && object.triggered !== undefined)
      return object;
    for (var child of [object?.autoRefreshTimer, object?.ipMonitorService]) {
      if (child) {
        var found = find(child);
        if (found)
          return found;
      }
    }
    for (var list of [object?.data, object?.children]) {
      if (!list || typeof list === "function" || typeof list.length !== "number")
        continue;
      for (var child of list) {
        var found = find(child);
        if (found)
          return found;
      }
    }
    return null;
  }
  Component.onCompleted: {
    manifest.waitForJob();
    var value = Number(Quickshell.env("POLL_EDGE_VALUE"));
    var configuration = {
      refreshInterval: value
    };
    var api = {
      pluginSettings: configuration,
      settingsContext: {
        settingsView: configuration,
        current: function () {
          return true;
        }
      },
      manifest: JSON.parse(manifest.text()),
      pluginDir: Quickshell.env("POLL_EDGE_CASE") + "/inert",
      tr: function (key) {
        return key;
      }
    };
    var component = Qt.createComponent("file://" + Quickshell.env("POLL_EDGE_PLUGIN") + "/Main.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString());
      Qt.exit(2);
      return;
    }
    main = component.createObject(null, {
                                    pluginApi: api
                                  });
  }
  Timer {
    interval: 80
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 60) {
        console.error("POLL_EDGE_TIMEOUT");
        Qt.exit(2);
        return;
      }
      if (!root.main || root.main.warpInstalled !== undefined && !root.main.warpInstalled || root.main.moniqueInstalled !== undefined && !root.main.moniqueInstalled)
        return;
      var timer = root.find(root.main);
      if (!timer)
        return;
      console.log("POLL_EDGE " + JSON.stringify({
                                                  input: Number(Quickshell.env("POLL_EDGE_VALUE")),
                                                  mainProjection: root.main.refreshInterval ?? root.main.ipMonitorService?.refreshInterval,
                                                  interval: timer.interval,
                                                  running: timer.running
                                                }));
      root.main.destroy();
      root.main = null;
      Qt.exit(0);
    }
  }
}
