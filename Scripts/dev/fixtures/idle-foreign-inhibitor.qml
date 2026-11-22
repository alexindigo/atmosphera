import DBus 1.0
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root
  property var pending
  property var cookie: null
  DBus {
    id: saver
    service: "org.freedesktop.ScreenSaver"
    path: "/org/freedesktop/ScreenSaver"
    iface: "org.freedesktop.ScreenSaver"
    connection: SessionBus
  }
  IpcHandler {
    target: "probe"
    function inhibit() {
      root.pending = saver.call("Inhibit", ["Idle regression", "Foreign inhibitor"]);
      var done = function () {
        if (!root.pending.isError)
          root.cookie = root.pending.values[0];
        console.log("INHIBITOR_REPLY", root.pending.isError, root.pending.values);
      };
      root.pending.finished.connect(done);
      if (root.pending.isFinished)
        done();
    }
    function release() {
      root.pending = saver.call("UnInhibit", [root.cookie]);
    }
  }
}
