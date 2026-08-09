pragma Singleton
import DBus 1.0

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// KeydService — owns the user-managed keyd layer (/etc/keyd/atmosphera) and
// triggers the root-side reload via systemd's D-Bus API. No CLI, no watcher:
// the shell writes the layer (user-owned by the package install hook) and
// starts atmosphera-keyd-reload.service in-process.
Singleton {
  id: root

  readonly property string layerFile: "/etc/keyd/atmosphera"

  function init() {
    _apply();
  }

  function _apply() {
    var env = "none";
    try {
      env = Settings.data.bindings.environment || "none";
    } catch (e) {}

    var src = (env === "macos") ? Quickshell.shellDir + "/Bindings/environments/macos/keyd/default.conf" : Quickshell.shellDir + "/Bindings/environments/macos/keyd/atmosphera.stub";

    // cat-truncate: the file is user-owned; install(1) would need write
    // permission on the root-owned /etc/keyd directory.
    var proc = Qt.createQmlObject(`
      import QtQuick
      import Quickshell.Io
      Process {
        command: ["sh", "-c", "cat \\"$1\\" > \\"$2\\"", "sh", "${src}", "${root.layerFile}"]
      }
    `, root, "KeydLayerWrite");

    proc.exited.connect(function (exitCode) {
      if (exitCode === 0) {
        Logger.d("KeydService", "Layer written:", root.layerFile, "env:", env);
        root._reload();
      } else {
        Logger.w("KeydService", "Cannot write", root.layerFile, "(exit", exitCode + ")", "— repair with: sudo atmosphera bindings apply-keyd", env);
      }
      proc.destroy();
    });
    proc.running = true;
  }

  // system bus handle to systemd's Manager
  property DBus _systemd: DBus {
    service: "org.freedesktop.systemd1"
    path: "/org/freedesktop/systemd1"
    iface: "org.freedesktop.systemd1.Manager"
    connection: SystemBus
  }

  function _reload() {
    // StartUnit(name, mode) — polkit rule Scripts/polkit/atmosphera-keyd.rules
    // lets active sessions / wheel start this one service without a prompt.
    root._systemd.call("StartUnit", ["atmosphera-keyd-reload.service", "replace"]);
    Logger.d("KeydService", "Requested keyd reload via systemd");
  }

  // Re-apply on bindings environment change
  Connections {
    target: Settings.data.bindings
    function onEnvironmentChanged() {
      Logger.i("KeydService", "Bindings environment changed — rewriting keyd layer");
      root._apply();
    }
  }
}
